WITH admissions_patients AS (
            SELECT
                ad.subject_id,
                ad.hadm_id,
                ad.admittime,
                ad.dischtime,
                ad.deathtime,
                ad.hospital_expire_flag,
                -- Calculate exact age at admission.
                -- anchor_age is age at anchor_year.
                -- age_at_admission = anchor_age + (admittime_year - anchor_year)
                pa.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - pa.anchor_year) AS age_at_admission,
                -- Calculate LOS in days
                DATE_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days,
                -- Calculate time to death in hours for non-survivors
                CASE
                    WHEN ad.hospital_expire_flag = 1 AND ad.deathtime IS NOT NULL
                    THEN DATE_DIFF(ad.deathtime, ad.admittime, HOUR)
                    ELSE NULL
                END AS time_to_death_hours
            FROM
                `physionet-data.mimiciv_3_1_hosp.admissions` ad
            JOIN
                `physionet-data.mimiciv_3_1_hosp.patients` pa
                ON ad.subject_id = pa.subject_id
            WHERE
                pa.gender = 'F'
                AND (pa.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - pa.anchor_year)) BETWEEN 53 AND 63
        ),
        -- Identify admissions with Septic Shock ICD codes
        adm_septic_shock AS (
            SELECT DISTINCT hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
            WHERE (icd_version = 10 AND icd_code IN ('R6521', 'T8112A')) -- ICD-10 Septic Shock
               OR (icd_version = 9 AND icd_code = '78552')           -- ICD-9 Septic Shock
        ),
        -- Identify admissions with Sepsis/Severe Sepsis ICD codes
        adm_sepsis AS (
            SELECT DISTINCT hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
            WHERE (icd_version = 10 AND (LEFT(icd_code, 3) IN ('A40', 'A41') OR icd_code = 'R6520')) -- ICD-10 Sepsis/Severe Sepsis
               OR (icd_version = 9 AND (LEFT(icd_code, 3) = '038' OR icd_code IN ('99591', '99592'))) -- ICD-9 Sepsis/Severe Sepsis
        ),
        sepsis_cohort AS (
            SELECT
                ap.hadm_id,
                ap.hospital_expire_flag,
                ap.los_days,
                ap.time_to_death_hours,
                -- Assign diagnosis group: Septic Shock takes precedence if identified
                CASE
                    WHEN ss.hadm_id IS NOT NULL THEN 'Septic Shock'
                    WHEN s.hadm_id IS NOT NULL THEN 'Sepsis'
                    ELSE 'Neither' -- Filter this out later
                END AS diagnosis_group,
                -- Assign LOS category
                CASE
                    WHEN ap.los_days <= 7 THEN 'LOS <= 7 days'
                    ELSE 'LOS > 7 days'
                END AS los_category
            FROM
                admissions_patients ap
            LEFT JOIN
                adm_septic_shock ss ON ap.hadm_id = ss.hadm_id
            LEFT JOIN
                adm_sepsis s ON ap.hadm_id = s.hadm_id
        ),
        grouped_stats AS (
            SELECT
                diagnosis_group,
                los_category,
                COUNT(DISTINCT hadm_id) AS N,
                SUM(hospital_expire_flag) AS num_deaths,
                SAFE_DIVIDE(SUM(hospital_expire_flag) * 100.0, COUNT(DISTINCT hadm_id)) AS mortality_percent,
                -- Median time-to-death for non-survivors. Use APPROX_QUANTILES for aggregate median.
                APPROX_QUANTILES(IF(hospital_expire_flag = 1, time_to_death_hours, NULL), 2)[OFFSET(1)] AS median_ttd_hours
            FROM
                sepsis_cohort
            WHERE
                diagnosis_group IN ('Sepsis', 'Septic Shock')
            GROUP BY
                diagnosis_group,
                los_category
        ),
        final_report_base AS (
          SELECT
            'Base Stats' AS comparison_type,
            diagnosis_group,
            los_category,
            CAST(NULL AS STRING) AS compared_to_group, -- Explicitly cast NULL to STRING
            N,
            ROUND(mortality_percent, 2) AS mortality_percent,
            ROUND(median_ttd_hours, 0) AS median_time_to_death_hours,
            CAST(NULL AS FLOAT64) AS absolute_mortality_difference,
            CAST(NULL AS FLOAT64) AS relative_mortality_difference_percent
          FROM grouped_stats
        ),
        -- Comparisons for Septic Shock vs Sepsis (within same LOS category)
        comparison_sepsis_vs_shock AS (
            SELECT
                'Diagnosis Comparison' AS comparison_type,
                ss.diagnosis_group AS diagnosis_group, -- The "primary" group for this comparison
                ss.los_category AS los_category,
                CONCAT('vs ', s.diagnosis_group) AS compared_to_group,
                CAST(NULL AS INT64) AS N, -- Explicitly cast NULL to correct type for UNION ALL
                CAST(NULL AS FLOAT64) AS mortality_percent,
                CAST(NULL AS FLOAT64) AS median_time_to_death_hours,
                ROUND(ss.mortality_percent - s.mortality_percent, 2) AS absolute_mortality_difference,
                ROUND(SAFE_DIVIDE(ss.mortality_percent - s.mortality_percent, s.mortality_percent) * 100.0, 2) AS relative_mortality_difference_percent
            FROM
                grouped_stats ss -- Septic Shock group
            JOIN
                grouped_stats s -- Sepsis group
                ON ss.los_category = s.los_category
            WHERE
                ss.diagnosis_group = 'Septic Shock' AND s.diagnosis_group = 'Sepsis'
        ),
        -- Comparisons for LOS > 7 days vs LOS <= 7 days (within same diagnosis group)
        comparison_los AS (
            SELECT
                'LOS Comparison' AS comparison_type,
                los_gt7.diagnosis_group AS diagnosis_group,
                los_gt7.los_category AS los_category, -- The "primary" LOS for this comparison
                CONCAT('vs ', los_le7.los_category) AS compared_to_group,
                CAST(NULL AS INT64) AS N, -- Explicitly cast NULL to correct type for UNION ALL
                CAST(NULL AS FLOAT64) AS mortality_percent,
                CAST(NULL AS FLOAT64) AS median_time_to_death_hours,
                ROUND(los_gt7.mortality_percent - los_le7.mortality_percent, 2) AS absolute_mortality_difference,
                ROUND(SAFE_DIVIDE(los_gt7.mortality_percent - los_le7.mortality_percent, los_le7.mortality_percent) * 100.0, 2) AS relative_mortality_difference_percent
            FROM
                grouped_stats los_gt7 -- LOS > 7 days group
            JOIN
                grouped_stats los_le7 -- LOS <= 7 days group
                ON los_gt7.diagnosis_group = los_le7.diagnosis_group
            WHERE
                los_gt7.los_category = 'LOS > 7 days' AND los_le7.los_category = 'LOS <= 7 days'
        )
        SELECT * FROM final_report_base
        UNION ALL
        SELECT * FROM comparison_sepsis_vs_shock
        UNION ALL
        SELECT * FROM comparison_los
ORDER BY
    CASE diagnosis_group
        WHEN 'Septic Shock' THEN 1
        WHEN 'Sepsis' THEN 2
        ELSE 99 -- Fallback for unexpected values
    END,
    CASE los_category
        WHEN 'LOS <= 7 days' THEN 1
        WHEN 'LOS > 7 days' THEN 2
        ELSE 99 -- Fallback
    END,
    CASE comparison_type
        WHEN 'Base Stats' THEN 1
        WHEN 'Diagnosis Comparison' THEN 2
        WHEN 'LOS Comparison' THEN 3
        ELSE 99 -- Fallback
    END;