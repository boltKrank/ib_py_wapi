# ib_py_wapi
Python Client usage for Infoblox WAPI


./fetch_nios_objects.sh -h 10.193.36.90 -u admin -p Infoblox@312 -v v2.12 -l resource_list.txt


Step 1:

Generate resource schema

Step 2:

Dump data

Step 3:

Convert data + schema = import.sh + manifest.tf

Run plan + apply to test.

Rich!!


## Generate Schema usage:

```bash
git clone https://github.com/infobloxopen/terraform-provider-infoblox.git
cd terraform-provider-infoblox
bash ../generate_resource_schema.sh infoblox/
```





# Teraform inmport notes



## CNAME attributes

| Attribute   | Required | Notes                                       |
| ----------- | -------- | ------------------------------------------- |
| `alias`     | **Yes**  | The alias FQDN (i.e., the CNAME itself)     |
| `canonical` | **Yes**  | The canonical target FQDN                   |
| `ttl`       | Optional | Default inherited from zone if unspecified  |
| `dns_view`  | Optional | DNS view (defaults to `"default"`)          |
| `comment`   | Optional | Descriptive comment                         |
| `ext_attrs` | Optional | Extensible attributes via `jsonencode(...)` |
