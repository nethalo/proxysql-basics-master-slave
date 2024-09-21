# ProxySQL - 101 Tutorial

This tutorial will help you walk through various aspects of setting up and use a basic ProxySQL installation. Enjoy!

## What is ProxySQL

ProxySQL is a lot of things, but what is worth for the current tutorial: Is a database traffic manager that acts as a query routing tool. It will add logic to the traffic distribution (in a very powerful way!) allowing us immediately  use the Read/Write Split features.

By just using it, you will also add a proxy later to shield the database, adds High-Availability to database topology and other fetaures available and waiting to be used, which are out of the scope of this tutorial, but  worth to be mentioned: 

- Query caching, Query rewrite, Query blocking
- Connection pooling and Multiplexing
- Read/Write Split, Read/Write Sharding
- Load balancing, Cluster Aware, Seamless failover
- Query mirroring, Query Throtttling, Query Timeout

## What is NOT ProxySQL

A failover tool. Is not a replacement of MHA/Orchestrator/etc… You'd still need to use a tool like that to perform the failovers. 

## Creating the tutorial environment

This tutorial uses Virtualbox and Vagrant. Is assumed that you are familiar with this tools (explanation of them is out of scope)

Follow this steps to get a setup:

### Install VirtualBox. 

Version 7.0.20 works. Download Virtualbox from [here](https://www.virtualbox.org/wiki/Downloads).

### Install Vagrant. 

Version 2.4.1 works. Download Vagrant from [here](http://vagrantup.com/).

### Create the environment

For this tutorial, the env consist of an "App" node (where ProxySQL will run) and 3 MySQLs, which will become 1 Primary and 2 Replicas.

![proxysql-Primary-slaves](https://raw.githubusercontent.com/nethalo/proxysql-basics-master-slave/master/proxysql-master-slaves.png)

### Clone the repo

```bash
git clone https://github.com/nethalo/proxysql-basics-master-slave.git
```

### Start the build

Run 

```bash
cd proxysql-basics-master-slave; vagrant plugin install vagrant-hostmanager; vagrant plugin install vagrant-vbguest; vagrant up; vagrant hostmanager;
```

The whole process takes a while the first time (around 20 minutes) so go grab some coffee and be back later.

Continue when the environment is done.

## Accessing the ProxySQL admin

The Admin can be accessed using the MySQL Cllient as if it was a regular MySQL installation, you just need to use the port 6032. The default credential values are admin/admin (user/pass):

```mysql
sudo -i;
mysql -u admin -padmin -h 127.0.0.1 -P6032 --prompt='Admin> '
```

You should be able to see this databases:

```mysql
Admin> show databases;
+-----+---------+-------------------------------+
| seq | name    | file                          |
+-----+---------+-------------------------------+
| 0   | main    |                               |
| 2   | disk    | /var/lib/proxysql/proxysql.db |
| 3   | stats   |                               |
| 4   | monitor |                               |
+-----+---------+-------------------------------+
4 rows in set (0.00 sec)
```

Let's configure everything for the Primary/Replica topology

## Configure the Primary/Replicas

On **mysql1**:

Connect to MySQL:
```shell
sudo -i;
mysql;
```
And run this:
```mysql
CREATE USER repl@'192.168.70.%' IDENTIFIED WITH mysql_native_password BY 'Replica+1';
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO repl@'192.168.70.%';
FLUSH PRIVILEGES;
```

On **mysql2** and **mysql3**:

Connect to MySQL:
```shell
sudo -i;
mysql;
```

```Mysql
CHANGE MASTER TO master_host = 'mysql1', master_user = 'repl', master_password='Replica+1', master_log_file = 'mysql-bin.000002', master_log_pos = 4; START REPLICA;
```

## Configuring ProxySQL

We need to make sure that ProxySQL is aware of this things:

- The MySQL servers
- The user that can connect to the servers (both the monit one and the "queries" one)
- Who is the Primary and who is/are the slave(s)

Let's start with the users

### Setting the Monit user

ProxySQL perform the monitoring checks using this user. This is needed for things like checking the value of the read_only variable.

This user requires the REPLICATION CLIENT grant for now. Just create it on the Primary and let the replication do the rest:

```mysql
CREATE USER repl@'app' IDENTIFIED WITH mysql_native_password BY 'Replica+1';
GRANT REPLICATION CLIENT ON *.* TO repl@'app';
FLUSH PRIVILEGES;
```

Now, on the admin side, update the values of the variables mysql-monitor_username and mysql-monitor_password:

```mysql
SET mysql-monitor_username='repl';
SET mysql-monitor_password='Replica+1';
```

Is this enough? 
NO!

Why?

Because the **Multi-Layer configuration** model of ProxySQL. Make sure you understand that: https://github.com/sysown/proxysql/wiki/Multi-layer-configuration-system

Okay, what is missing? Moving the configuration from memory to the Runtime layer and Persist the configuration on disk. To do that, execute:

```MySQL
LOAD MYSQL VARIABLES TO RUNTIME;
SAVE MYSQL VARIABLES TO DISK;
```

Now the change is really done.

### Setting the backend MySQL user

ProxySQL needs the username and the password of the user that can connect to the backend servers (the MySQL dbs). We need to provide that, but before we need to create the user in the dbs. 

In the Primary, create the user:

```Mysql
CREATE USER proxysql@'%' IDENTIFIED WITH mysql_native_password BY 'Proxysql+1';
GRANT ALL PRIVILEGES ON *.* TO proxysql@'%';
FLUSH PRIVILEGES;
```

And now let ProxySQL know the data:

```MySQL
INSERT INTO mysql_users (username,password, default_hostgroup) VALUES ('proxysql','Proxysql+1',1);
```

Remember to load it to Runtime. To do that, execute:

```mysql
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS TO DISK;
```

Now the config is actually on runtime.

### Setting the servers

Server info is stored in the **mysql_servers** table. The most basic amount of info required to insert is the info that describes:

- The server hostname
- The MySQL port
- And the hostgroup where the server belongs. And this is where the concep of ***Replication Hostgroup*** becomes relevant, so let's define it

#### Replication hostgroup

You can add a server to all the hostgroups that you want. This will help on the query routing (eventually the hostgroup is the destination of the query rlues) and to have a controlled load distribution, among other things.

However, ProxySQL in an effort to simplify things have the special "replication hostgroup" type which is nothing that a way to say which hostgroup holds the Primary and which one holds the Replicas. 

How is this different to a regular hostgroup? Simply: The task of moving servers between hostgroups becomes an automatic operation and depends on only one thing: the value of the **read_only** variable. 

If a server has "read_only = 1" it will be part of the reader_hostgroup. Otherwise, is the Primary and is part of the writer_hostgroup. This means that you need to be extra careful with this variable. A good practice will be to enforce read_only = 1 on the my.cnf file and just change it on the fly in the Primary. 

To define the replication hostgroup, just do a insert to the mysql_replication_hostgroups table. For this tutorial, the insert is:

```mysql
INSERT INTO mysql_replication_hostgroups (writer_hostgroup, reader_hostgroup) VALUES(1,2);
```

### Adding the MySQL servers to ProxySQL

Let's add the server, but before a note:

*NOTE: If you wish that the Primary gets not only "write" traffic but also "read" traffic, it needs to belong to both hostgroups. A way to achieve this is by setting read_only=1 on the Primary before inserting it and then after the insert rollback the value to readn_only=0. Or you just could add it directly to both hostgroups.*

Now,  the inserts:

```mysql
INSERT INTO mysql_servers (hostgroup_id, hostname, port, weight) VALUES (1,'mysql1',3306,1);
INSERT INTO mysql_servers (hostgroup_id, hostname, port, weight) VALUES (2,'mysql2',3306,1);
INSERT INTO mysql_servers (hostgroup_id, hostname, port, weight) VALUES (2,'mysql3',3306,1);
```

Remember to move the configuration to runtime:

```MySQL
LOAD MYSQL SERVERS TO RUNTIME;
SAVE MYSQL SERVERS TO DISK;
```

### Setting Query Rules

At least, in the most basic configuration, we need to set 2 query rules.

- All the SELECT … FOR UPDATE goes to the writer hostgroup
- The remaining SELECTs goes to the reader hostgroup

To set the rules, we need to add rows to the **mysql_query_rules** table.

```mysql
INSERT INTO mysql_query_rules (active, match_pattern, destination_hostgroup, cache_ttl) VALUES (1, '^SELECT .* FOR UPDATE', 1, NULL);
INSERT INTO mysql_query_rules (active, match_pattern, destination_hostgroup, cache_ttl) VALUES (1, '^SELECT .*', 2, NULL);
```

Move it to runtime:

```mysql
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
```

## Checks

Let's verify that things works as expected.

### Check the mysql_server status

Verify that the Primary and the Replicas are part of the hostgroups that they belong. For this query the runtime_mysql_servers table:

```mysql
mysql> SELECT hostgroup_id,hostname,port,status FROM runtime_mysql_servers;
+--------------+----------+------+--------+
| hostgroup_id | hostname | port | status |
+--------------+----------+------+--------+
| 1            | mysql1   | 3306 | ONLINE |
| 2            | mysql1   | 3306 | ONLINE |
| 2            | mysql3   | 3306 | ONLINE |
| 2            | mysql2   | 3306 | ONLINE |
+--------------+----------+------+--------+
4 rows in set (0.00 sec)
```

Perfect!

### Check that the routing works

This is where we learn how ProxySQL acts as the database frontend. Is just like accesing the admin but this time using the **port 6033**

To verify the routing, let's check for the hostname:

```mysql
mysql -uproxysql -pProxysql+1 -h 127.0.0.1 -P6033 -e "START TRANSACTION; SELECT @@hostname; ROLLBACK;"
```

As expected, it returns "mysql1":

```Mysql
[root@app ~]# mysql -uproxysql -pProxysql+1 -h 127.0.0.1 -P6033 -e "START TRANSACTION; SELECT @@hostname; ROLLBACK;"
Warning: Using a password on the command line interface can be insecure.
+------------+
| @@hostname |
+------------+
| mysql1     |
+------------+
```

What about if we change the Primary? Let's set mysql1 as read only and make mysql3 the new Primary (by setting read_only = 0)

Verify that ProxySQL is aware of the new Primary and has moved it to the writer_hostgroup:

```Mysql
mysql> SELECT hostgroup_id,hostname,port,status FROM runtime_mysql_servers;
+--------------+----------+------+--------+
| hostgroup_id | hostname | port | status |
+--------------+----------+------+--------+
| 1            | mysql3   | 3306 | ONLINE |
| 2            | mysql1   | 3306 | ONLINE |
| 2            | mysql3   | 3306 | ONLINE |
| 2            | mysql2   | 3306 | ONLINE |
+--------------+----------+------+--------+
4 rows in set (0.00 sec)
```

And now via query:

```mysql
[root@app ~]# mysql -uproxysql -pProxysql+1 -h 127.0.0.1 -P6033 -e "START TRANSACTION; SELECT @@hostname; ROLLBACK;"
Warning: Using a password on the command line interface can be insecure.
+------------+
| @@hostname |
+------------+
| mysql3     |
+------------+
```

Perfect!

**Does this means that mysql3 is the really the new Primary?** 
NO!

**What happened then?** 
ProxySQL is NOT a failover tool. Like we mention at the beggining, is a routing tool. What happen is that since we are using the special Replication hostgroup feature, ProxySQL was informed that the Primary changed by changing the read_only variable, but mysql1 was still the Primary and mysql2 and mysql3 were still replicating from it. 

**What if we just do "SELECT @@hostname;"? No explicitly transaction involved.**

In this case, the hostname will be any of the read_hostgrpup members, which is all of our MySQLs. So it can be mysql1, mysql2 or mysql3. Give it a try.
