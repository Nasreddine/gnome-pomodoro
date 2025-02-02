/*
 * This file is part of GNOME Pomodoro
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 *
 */

namespace Pomodoro
{
    public class ApplicationTest : Pomodoro.TestSuite
    {
        public ApplicationTest ()
        {
//            this.add_test ("timer_restore",
//                           this.test_timer_restore);
        }

        public override void setup () {
//            var settings = Pomodoro.get_settings ()
//                                   .get_child ("preferences");
//            settings.set_double ("pomodoro-duration", POMODORO_DURATION);
//            settings.set_double ("short-break-duration", SHORT_BREAK_DURATION);
//            settings.set_double ("long-break-duration", LONG_BREAK_DURATION);
//            settings.set_double ("long-break-interval", LONG_BREAK_INTERVAL);
//            settings.set_boolean ("pause-when-idle", false);
        }

        public override void teardown () {
            var settings = Pomodoro.get_settings ();
            settings.revert ();
        }

        public void test_save ()
        {
            var settings = Pomodoro.get_settings ()
                                   .get_child ("state");

            var timer = new Pomodoro.Timer();

            /* TODO */
        }

        /**
         * Unit test for Pomodoro.Timer.restore() method.
         *
         * Check whether restoring timer works correctly.
         */
        public void test_restore ()
        {
            var settings = Pomodoro.get_settings ()
                                   .get_child ("state");

            var timer = new Pomodoro.Timer();

            /* TODO */
        }
    }
}
