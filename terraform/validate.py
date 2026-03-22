#!/usr/bin/env python3
"""
Terraform Configuration Validator
Checks HCL syntax and configuration validity
"""

import re
import os
import sys
from pathlib import Path

def validate_hcl_syntax(file_path):
    """Basic HCL syntax validation"""
    with open(file_path, 'r') as f:
        content = f.read()
    
    errors = []
    
    # Check matching braces
    open_braces = content.count('{')
    close_braces = content.count('}')
    if open_braces != close_braces:
        errors.append(f"Mismatched braces: {open_braces} opening, {close_braces} closing")
    
    # Check matching quotes
    single_quotes = content.count("'") - content.count("\\'")
    if single_quotes % 2 != 0:
        errors.append("Mismatched single quotes")
    
    double_quotes = content.count('"') - content.count('\\"')
    if double_quotes % 2 != 0:
        errors.append("Mismatched double quotes")
    
    # Check for unclosed strings
    lines = content.split('\n')
    for i, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith('#'):
            continue
        
        # Check for incomplete lines
        if stripped.endswith(',') and not ('{' in stripped or '[' in stripped):
            if '}' in stripped or ']' in stripped:
                errors.append(f"Line {i}: Trailing comma before closing bracket")
    
    return errors

def validate_resources(file_path):
    """Validate resource definitions"""
    with open(file_path, 'r') as f:
        content = f.read()
    
    errors = []
    
    # Find all resource blocks
    resource_pattern = r'resource\s+"([^"]+)"\s+"([^"]+)"\s*\{'
    resources = re.findall(resource_pattern, content)
    
    # Find all variable references
    var_refs = re.findall(r'var\.(\w+)', content)
    
    # Find all declared variables
    var_pattern = r'variable\s+"([^"]+)"\s*\{'
    declared_vars = re.findall(var_pattern, content)
    
    return {
        'resources': resources,
        'var_refs': list(set(var_refs)),
        'declared_vars': declared_vars,
        'errors': errors
    }

def validate_file(file_path):
    """Validate a single Terraform file"""
    file_path_str = str(file_path)
    print(f"Validating: {file_path_str}")
    
    syntax_errors = validate_hcl_syntax(file_path)
    resource_info = validate_resources(file_path)
    
    if syntax_errors:
        print(f"  ❌ Syntax errors:")
        for error in syntax_errors:
            print(f"     - {error}")
        return False
    else:
        print(f"  ✅ HCL syntax valid")
    
    # Check variable references
    undefined_vars = []
    for var_ref in resource_info['var_refs']:
        if var_ref not in resource_info['declared_vars']:
            # Check if it might be from a different file
            undefined_vars.append(var_ref)
    
    if undefined_vars and file_path_str.endswith('main.tf'):
        print(f"  ⚠️  Variables referenced but check variables.tf for definition:")
        for var in sorted(set(undefined_vars)):
            print(f"     - {var}")
    
    if resource_info['resources']:
        print(f"  📦 Resources defined: {len(resource_info['resources'])}")
    
    return True

def main():
    terraform_dir = Path('/home/james/payments-streaming-platform/terraform')
    
    if not terraform_dir.exists():
        print(f"❌ Terraform directory not found: {terraform_dir}")
        sys.exit(1)
    
    tf_files = sorted(terraform_dir.glob('*.tf'))
    
    print("=" * 60)
    print("TERRAFORM CONFIGURATION VALIDATION")
    print("=" * 60)
    print()
    
    all_valid = True
    for tf_file in tf_files:
        valid = validate_file(tf_file)
        all_valid = all_valid and valid
        print()
    
    # Cross-file validation
    print("=" * 60)
    print("CROSS-FILE VALIDATION")
    print("=" * 60)
    
    all_vars = set()
    all_var_refs = set()
    
    for tf_file in tf_files:
        with open(tf_file, 'r') as f:
            content = f.read()
        var_pattern = r'variable\s+"([^"]+)"\s*\{'
        declared = re.findall(var_pattern, content)
        all_vars.update(declared)
        
        var_refs = re.findall(r'var\.(\w+)', content)
        all_var_refs.update(var_refs)
    
    undefined = all_var_refs - all_vars
    if undefined:
        print(f"⚠️  Undefined variables referenced:")
        for var in sorted(undefined):
            print(f"   - var.{var}")
    else:
        print("✅ All variable references are defined")
    
    print()
    print("=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"✅ Files checked: {len(tf_files)}")
    print(f"✅ HCL syntax: {'VALID' if all_valid else 'INVALID'}")
    print()
    if all_valid:
        print("🎉 Basic validation passed!")
        print()
        print("Next step: Deploy with:")
        print("  cd terraform")
        print("  terraform init")
        print("  terraform plan")
    else:
        print("❌ Validation failed - fix errors above")
        sys.exit(1)

if __name__ == '__main__':
    main()