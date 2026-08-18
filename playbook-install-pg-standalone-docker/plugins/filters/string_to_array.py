#!/usr/bin/env python3
"""Custom Ansible filter to convert multiline strings to arrays."""


def string_to_array(value, preserve_empty=False):
    """Convert a multiline string into an array of strings."""
    if not isinstance(value, str):
        return [str(value)]
    
    lines = value.split('\n')
    
    if preserve_empty:
        return lines
    else:
        return [line for line in lines if line.strip()]


class FilterModule(object):
    """Ansible filter module class."""
    
    def filters(self):
        """Return filter functions dictionary."""
        return {
            'string_to_array': string_to_array,
        }
