WITH base_cohort_info AS (
            SELECT
                adm.subject_id,
                adm.hadm_id,
                adm.admittime,
                adm.dischtime,
                adm.hospital_expire_flag,
                -- Calculate age at admission
                CAST(pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS INT64) AS age_at_admission,
                -- Calculate Length of Stay in days
                DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
            FROM
                `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
            INNER JOIN
                `physionet-data.mimiciv_3_1_hosp.patients` AS pat
                ON adm.subject_id = pat.subject_id
            WHERE
                pat.gender = 'F'
                AND CAST(pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS INT64) BETWEEN 62 AND 72
        ),
        -- Step 2: Identify AMI admissions
        ami_admissions AS (
            SELECT DISTINCT hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
            WHERE
                (icd_version = 9 AND icd_code LIKE '410%') -- AMI ICD-9 (410.XX)
                OR (icd_version = 10 AND icd_code LIKE 'I21%') -- AMI ICD-10 (I21.XX)
        ),
        -- Step 3: Identify a list of Admissions with Shock diagnoses (to EXCLUDE)
        shock_admissions AS (
            SELECT DISTINCT hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
            WHERE
                (icd_version = 9 AND icd_code LIKE '7855%') -- Shock ICD-9 (785.50-785.59)
                OR (icd_version = 10 AND (icd_code LIKE 'R57%' OR icd_code = 'I9581')) -- Shock ICD-10 (R57.XX, I95.81 for cardiogenic shock)
        ),
        -- Step 4: Identify a list of Admissions with Respiratory Failure diagnoses (to EXCLUDE)
        resp_fail_admissions AS (
            SELECT DISTINCT hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
            WHERE
                (icd_version = 9 AND (icd_code LIKE '51881%' OR icd_code LIKE '51883%' OR icd_code LIKE '51884%')) -- Acute/Chronic respiratory failure ICD-9
                OR (icd_version = 10 AND icd_code LIKE 'J96%') -- Respiratory failure ICD-10 (J96.XX)
        ),
        -- Step 5: Identify Admissions with CKD diagnoses (for prevalence)
        ckd_admissions AS (
            SELECT DISTINCT hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
            WHERE
                (icd_version = 9 AND icd_code LIKE '585%') -- CKD ICD-9 (585.XX)
                OR (icd_version = 10 AND icd_code LIKE 'N18%') -- CKD ICD-10 (N18.XX)
        ),
        -- Step 6: Identify Admissions with Diabetes diagnoses (for prevalence)
        diabetes_admissions AS (
            SELECT DISTINCT hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
            WHERE
                (icd_version = 9 AND icd_code LIKE '250%') -- Diabetes ICD-9 (250.XX)
                OR (icd_version = 10 AND (icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%')) -- Diabetes ICD-10 (E10.XX, E11.XX, E13.XX)
        ),
        -- Step 7: Apply all filters to form the final analytical cohort
        final_cohort AS (
            SELECT
                bci.subject_id,
                bci.hadm_id,
                bci.hospital_expire_flag,
                bci.los_days,
                CASE
                    WHEN bci.los_days <= 5 THEN 'LOS_LE_5D'
                    ELSE 'LOS_GT_5D'
                END AS los_group,
                CASE WHEN ckd.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_ckd,
                CASE WHEN db.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_diabetes
            FROM
                base_cohort_info AS bci
            INNER JOIN
                ami_admissions AS ami
                ON bci.hadm_id = ami.hadm_id
            LEFT JOIN
                shock_admissions AS shock
                ON bci.hadm_id = shock.hadm_id
            LEFT JOIN
                resp_fail_admissions AS rf
                ON bci.hadm_id = rf.hadm_id
            LEFT JOIN
                ckd_admissions AS ckd
                ON bci.hadm_id = ckd.hadm_id
            LEFT JOIN
                diabetes_admissions AS db
                ON bci.hadm_id = db.hadm_id
            WHERE
                shock.hadm_id IS NULL -- Exclude patients with shock
                AND rf.hadm_id IS NULL -- Exclude patients with respiratory failure
        ),
        -- Step 8: Calculate group-wise statistics
        grouped_stats AS (
            SELECT
                los_group,
                COUNT(DISTINCT hadm_id) AS total_patients,
                SUM(hospital_expire_flag) AS total_deaths,
                SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(DISTINCT hadm_id)) * 100 AS mortality_rate,
                SAFE_DIVIDE(SUM(has_ckd), COUNT(DISTINCT hadm_id)) * 100 AS ckd_prevalence,
                SAFE_DIVIDE(SUM(has_diabetes), COUNT(DISTINCT hadm_id)) * 100 AS diabetes_prevalence
            FROM
                final_cohort
            GROUP BY
                los_group
        )
-- Final Step: Report requested statistics and calculate differences
SELECT
    gs.los_group,
    gs.total_patients,
    gs.total_deaths,
    gs.mortality_rate,
    gs.ckd_prevalence,
    gs.diabetes_prevalence,
    -- Calculate absolute mortality difference (LOS_GT_5D compared to LOS_LE_5D)
    CASE
        WHEN gs.los_group = 'LOS_GT_5D' THEN
            gs.mortality_rate - (SELECT mortality_rate FROM grouped_stats WHERE los_group = 'LOS_LE_5D')
        ELSE NULL
    END AS absolute_mortality_difference_from_le_5d,
    -- Calculate relative mortality difference (LOS_GT_5D compared to LOS_LE_5D)
    CASE
        WHEN gs.los_group = 'LOS_GT_5D' THEN
            SAFE_DIVIDE(
                (gs.mortality_rate - (SELECT mortality_rate FROM grouped_stats WHERE los_group = 'LOS_LE_5D')),
                (SELECT mortality_rate FROM grouped_stats WHERE los_group = 'LOS_LE_5D')
            ) * 100
        ELSE NULL
    END AS relative_mortality_difference_from_le_5d_pct
FROM
    grouped_stats gs
ORDER BY
    gs.los_group DESC;