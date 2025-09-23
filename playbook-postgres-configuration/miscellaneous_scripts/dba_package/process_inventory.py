import yaml
from pathlib import Path

class Inventory:
    inventory_file:str = None
    inventory_content:str = None
    inventory_hosts:list = list()
    inventory_items:list = list()
    max_depth = 20

    def __init__(self, inventory_file):
        Inventory.inventory_file = self.__get_file_path(inventory_file)
        Inventory.inventory_content = self.__get_file_content()
        Inventory.inventory_hosts = self.__extract_hosts(Inventory.inventory_content)
        Inventory.inventory_items = self.__extract_inventory_items(Inventory.inventory_content)
        self.depth = Inventory.max_depth

    def __get_file_path(self, inventory_file):
        inventory_file_path = inventory_file
        if inventory_file.find('\\') == -1:
            # file name provided
            base_dir = Path(__file__).resolve().parent.parent
            inventory_file_path = (base_dir / inventory_file).resolve()

        if not inventory_file_path.is_file():
            raise FileNotFoundError(f'File not found: {inventory_file_path}')

        return inventory_file_path

    def __get_file_content(self):
        file_content = None

        # Load inventory yaml file
        with open(Inventory.inventory_file, "r") as f:
            file_content = yaml.safe_load(f)

        return file_content

    def __extract_hosts(self, content_to_parse):
        '''
        Purpose: Extract and return host names from Ansible YAML Inventory content
        INPUTS: Ansible YAML Inventory Content
        OUTPUT: List of host names
        '''
        hosts = []
        if isinstance(content_to_parse, dict):
            if 'hosts' in content_to_parse and isinstance(content_to_parse['hosts'], dict):
                hosts.extend(content_to_parse['hosts'].keys())
            for key in content_to_parse:
                hosts.extend(self.__extract_hosts(content_to_parse[key]))
        return hosts

    def __extract_inventory_items(self, inventory_content):
        """
        Parse an Ansible inventory YAML file into a list of dictionaries.

        Each dictionary will have:
        ansible_host, ip, stanza_name, master_dns_name, replica_dns_name
        """

        rows = []

        def extract_hosts(hosts_dict):
            """Extract host info from a dict of hosts"""
            if not hosts_dict:   # <-- skip None or empty dict
                return
            for host, attrs in hosts_dict.items():
                rows.append({
                    "ansible_host": host,
                    "ip": attrs.get("ip") if isinstance(attrs, dict) else None,
                    "stanza_name": attrs.get("stanza_name") if isinstance(attrs, dict) else None,
                    "master_dns_name": attrs.get("master_dns_name") if isinstance(attrs, dict) else None,
                    "replica_dns_name": attrs.get("replica_dns_name") if isinstance(attrs, dict) else None,
                })

        def recurse(node):
            """Recursively walk the inventory tree"""
            if not isinstance(node, dict):
                return
            if "hosts" in node:
                extract_hosts(node["hosts"])
            if "children" in node:
                for child in node["children"].values():
                    recurse(child)

        recurse(inventory_content.get("all", {}))

        return rows

    def get_hosts_from_group(self, content_to_parse=None, group_name='all'):
        """
        Recursively extract all hosts under the specified group name,
        including all nested children.
        """
        if not content_to_parse:
            content_to_parse = Inventory.inventory_content

        if group_name == 'all':
            group_node = content_to_parse.get('all', {})
        else:
            group_node = self.__find_group_node(content_to_parse.get('all', {}), group_name)

        if not group_node:
            return []

        return self.__extract_hosts(group_node)

    def __find_group_node(self, node, group_name):
        """
        Recursively search for the dictionary node corresponding to the group_name.
        """
        if not isinstance(node, dict):
            return None

        for key, value in node.get('children', {}).items():
            if key == group_name:
                return value
            result = self.__find_group_node(value, group_name)
            if result:
                return result
        return None

# from miscellaneous_scripts.dba_package.process_inventory import Inventory
# inv = Inventory("hosts.yml")
# inv = Inventory("/home/saanvi/Documents/Github/Office-Repos/postgres-install-automation/hosts_all.yml")
# inv.inventory_file
# inv.inventory_hosts
# inv.inventory_items
# df_inventory = pd.DataFrame(inv.inventory_items)
# df_inventory.columns
# df_inventory[['ansible_host','ip','stanza_name']]

# inv.inventory_content
# inv.get_hosts_from_group(group_name='leader')
# inv.get_hosts_from_group(group_name='leaders')
# inv.get_hosts_from_group(group_name='standby_leader')
# inv.get_hosts_from_group(group_name='replicas')
# inv.get_hosts_from_group(group_name='non_clustered')
# inv.get_hosts_from_group(group_name='all')
# inv.get_hosts_from_group(group_name='clustered')

