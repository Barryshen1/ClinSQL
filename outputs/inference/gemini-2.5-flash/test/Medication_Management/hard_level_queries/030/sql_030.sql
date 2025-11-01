WITH cohort_patients AS (
    -- 1. Identify the target cohort: Female inpatients, aged 71-81, with acute pancreatitis
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON ad.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON ad.hadm_id = di.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 71 AND 81 -- Using anchor_age as a proxy for age during admission
        AND (
            (di.icd_version = 9 AND di.icd_code = '5770') OR -- ICD-9 for Acute Pancreatitis
            (di.icd_version = 10 AND di.icd_code LIKE 'K85%') -- ICD-10 for Acute Pancreatitis (e.g., K85, K85.0, K85.1, etc.)
        )
    GROUP BY -- Ensure one row per admission, even if multiple matching diagnoses
        ad.subject_id, ad.hadm_id, ad.admittime, ad.dischtime, ad.hospital_expire_flag
),
medication_complexity AS (
    -- 2. Calculate medication complexity score: Count of distinct drugs prescribed in the first 72 hours
    SELECT
        cp.subject_id,
        cp.hadm_id,
        COUNT(DISTINCT pr.drug) AS med_complexity_score
    FROM
        cohort_patients AS cp
    LEFT JOIN -- Use LEFT JOIN to include patients with 0 medications in the timeframe
        `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
        ON cp.subject_id = pr.subject_id
        AND cp.hadm_id = pr.hadm_id
        AND pr.starttime BETWEEN cp.admittime AND TIMESTAMP_ADD(cp.admittime, INTERVAL 72 HOUR)
    GROUP BY
        cp.subject_id, cp.hadm_id
),
readmission_30d AS (
    -- 3. Determine 30-day readmission status for each admission
    SELECT
        cp.subject_id,
        cp.hadm_id,
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS next_adm
                WHERE
                    next_adm.subject_id = cp.subject_id
                    AND next_adm.hadm_id != cp.hadm_id -- Must be a different admission
                    AND next_adm.admittime BETWEEN cp.dischtime AND TIMESTAMP_ADD(cp.dischtime, INTERVAL 30 DAY)
            ) THEN 1
            ELSE 0
        END AS readmission_30d_flag
    FROM
        cohort_patients AS cp
),
combined_cohort_data AS (
    -- 4. Combine all required data and calculate LOS
    SELECT
        cp.subject_id,
        cp.hadm_id,
        cp.hospital_expire_flag,
        COALESCE(mc.med_complexity_score, 0) AS med_complexity_score, -- Assign 0 if no medications found
        rd.readmission_30d_flag,
        DATE_DIFF(cp.dischtime, cp.admittime, HOUR) / 24.0 AS los_days -- Length of stay in days
    FROM
        cohort_patients AS cp
    LEFT JOIN
        medication_complexity AS mc
        ON cp.subject_id = mc.subject_id AND cp.hadm_id = mc.hadm_id
    LEFT JOIN
        readmission_30d AS rd
        ON cp.subject_id = rd.subject_id AND cp.hadm_id = rd.hadm_id
),
cohort_with_tertiles AS (
    -- 5. Assign tertiles based on the medication complexity score
    SELECT
        subject_id,
        hadm_id,
        med_complexity_score,
        los_days,
        hospital_expire_flag,
        readmission_30d_flag,
        NTILE(3) OVER (ORDER BY med_complexity_score ASC) AS med_complexity_tertile
    FROM
        combined_cohort_data
)
-- 6. Report outcomes per tertile
SELECT
    med_complexity_tertile,
    COUNT(hadm_id) AS num_admissions_in_tertile,
    MIN(med_complexity_score) AS min_med_complexity_score,
    MAX(med_complexity_score) AS max_med_complexity_score,
    AVG(los_days) AS avg_los_days,
    AVG(hospital_expire_flag) AS in_hospital_mortality_rate, -- Average of binary 0/1 flag gives the rate
    AVG(readmission_30d_flag) AS thirty_day_readmission_rate -- Average of binary 0/1 flag gives the rate
FROM
    cohort_with_tertiles
GROUP BY
    med_complexity_tertile
ORDER BY
    med_complexity_tertile;