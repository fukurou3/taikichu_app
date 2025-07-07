#!/usr/bin/env python3
"""
管理者権限設定スクリプト

Firebase Admin SDKを使用してユーザーにカスタムクレーム（役割）を設定します。

使用例:
    python setup_admin_roles.py set-role <user_uid> superadmin
    python setup_admin_roles.py set-role <user_uid> moderator
    python setup_admin_roles.py remove-role <user_uid>
    python setup_admin_roles.py list-admins
"""

import argparse
import sys
from firebase_admin import credentials, initialize_app, auth

def initialize_firebase():
    """Firebase Admin SDK を初期化"""
    try:
        # デフォルトのサービスアカウント認証を使用
        initialize_app()
        print("✓ Firebase Admin SDK initialized successfully")
    except Exception as e:
        print(f"✗ Failed to initialize Firebase Admin SDK: {e}")
        sys.exit(1)

def set_user_role(uid: str, role: str):
    """
    ユーザーに役割を設定
    
    Args:
        uid: ユーザーUID
        role: 役割 ('superadmin' or 'moderator')
    """
    valid_roles = ['superadmin', 'moderator']
    
    if role not in valid_roles:
        print(f"✗ Invalid role: {role}. Must be one of: {valid_roles}")
        return False
    
    try:
        # ユーザーが存在するかチェック
        user_record = auth.get_user(uid)
        print(f"Found user: {user_record.email or user_record.uid}")
        
        # カスタムクレームを設定
        auth.set_custom_user_claims(uid, {'role': role})
        
        print(f"✓ Successfully set role '{role}' for user {uid}")
        
        # 設定確認
        updated_user = auth.get_user(uid)
        claims = updated_user.custom_claims
        print(f"  Current claims: {claims}")
        
        return True
        
    except auth.UserNotFoundError:
        print(f"✗ User not found: {uid}")
        return False
    except Exception as e:
        print(f"✗ Error setting role: {e}")
        return False

def remove_user_role(uid: str):
    """
    ユーザーの役割を削除
    
    Args:
        uid: ユーザーUID
    """
    try:
        # ユーザーが存在するかチェック
        user_record = auth.get_user(uid)
        print(f"Found user: {user_record.email or user_record.uid}")
        
        # カスタムクレームを削除
        auth.set_custom_user_claims(uid, None)
        
        print(f"✓ Successfully removed role for user {uid}")
        
        return True
        
    except auth.UserNotFoundError:
        print(f"✗ User not found: {uid}")
        return False
    except Exception as e:
        print(f"✗ Error removing role: {e}")
        return False

def list_admin_users(limit: int = 100):
    """
    管理者権限を持つユーザー一覧を表示
    
    Args:
        limit: 検索するユーザー数の上限
    """
    try:
        print(f"Searching for admin users (limit: {limit})...")
        
        # すべてのユーザーを取得してフィルタリング
        page = auth.list_users(max_results=limit)
        admin_users = []
        
        while page:
            for user in page.users:
                if user.custom_claims and 'role' in user.custom_claims:
                    role = user.custom_claims['role']
                    if role in ['superadmin', 'moderator']:
                        admin_users.append({
                            'uid': user.uid,
                            'email': user.email,
                            'role': role,
                            'disabled': user.disabled,
                            'last_sign_in': user.user_metadata.last_sign_in_timestamp
                        })
            
            # 次のページがあるかチェック
            if page.has_next_page:
                page = page.get_next_page()
            else:
                break
        
        if not admin_users:
            print("No admin users found.")
            return
        
        print(f"\nFound {len(admin_users)} admin user(s):")
        print("-" * 80)
        print(f"{'UID':<28} {'Email':<30} {'Role':<12} {'Status'}")
        print("-" * 80)
        
        for user in admin_users:
            status = "Disabled" if user['disabled'] else "Active"
            email = user['email'] or "(no email)"
            print(f"{user['uid']:<28} {email:<30} {user['role']:<12} {status}")
        
    except Exception as e:
        print(f"✗ Error listing admin users: {e}")

def main():
    parser = argparse.ArgumentParser(description="Firebase Admin Role Management")
    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    
    # set-role コマンド
    set_parser = subparsers.add_parser('set-role', help='Set user role')
    set_parser.add_argument('uid', help='User UID')
    set_parser.add_argument('role', choices=['superadmin', 'moderator'], help='Role to assign')
    
    # remove-role コマンド
    remove_parser = subparsers.add_parser('remove-role', help='Remove user role')
    remove_parser.add_argument('uid', help='User UID')
    
    # list-admins コマンド
    list_parser = subparsers.add_parser('list-admins', help='List admin users')
    list_parser.add_argument('--limit', type=int, default=100, help='Max users to check (default: 100)')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return
    
    # Firebase初期化
    initialize_firebase()
    
    # コマンド実行
    if args.command == 'set-role':
        success = set_user_role(args.uid, args.role)
        sys.exit(0 if success else 1)
    
    elif args.command == 'remove-role':
        success = remove_user_role(args.uid)
        sys.exit(0 if success else 1)
    
    elif args.command == 'list-admins':
        list_admin_users(args.limit)

if __name__ == '__main__':
    main()