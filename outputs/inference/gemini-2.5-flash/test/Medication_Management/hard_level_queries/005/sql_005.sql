WITH cohort_admissions AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        pat.gender,
        pat.anchor_age
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 43 AND 53
        -- Filter for hepatic failure diagnosis
        AND adm.hadm_id IN (
            SELECT DISTINCT dia.hadm_id
            FROM
                `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dia
            WHERE
                (dia.icd_version = 9 AND dia.icd_code = '5722') -- 572.2 Hepatic coma (e.g. from chronic liver disease)
                OR (dia.icd_version = 10 AND dia.icd_code LIKE 'K72%') -- K72 family: Hepatic failure, not elsewhere classified
        )
),
-- Step 2: Calculate medication complexity score for the first 72 hours and LOS.
medication_scores AS (
    SELECT
        ca.subject_id,
        ca.hadm_id,
        ca.admittime,
        ca.dischtime,
        ca.hospital_expire_flag,
        -- Count distinct medications from EMAR within the first 72 hours of admission
        COALESCE(COUNT(DISTINCT emar.medication), 0) AS medication_complexity_score,
        DATETIME_DIFF(ca.dischtime, ca.admittime, HOUR) / 24.0 AS los_days
    FROM
        cohort_admissions ca
    LEFT JOIN -- Use LEFT JOIN to include patients with 0 medications in 72h
        `physionet-data.mimiciv_3_1_hosp.emar` emar
        ON ca.subject_id = emar.subject_id
        AND ca.hadm_id = emar.hadm_id
        AND emar.charttime BETWEEN ca.admittime AND TIMESTAMP_ADD(ca.admittime, INTERVAL 72 HOUR)
    GROUP BY
        ca.subject_id, ca.hadm_id, ca.admittime, ca.dischtime, ca.hospital_expire_flag
),
-- Step 3: Identify the next admission for each patient using window functions (corrected the LATERAL JOIN).
admissions_with_next_adm AS (
    SELECT
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        -- Use LEAD to get the admittime of the next admission for the same subject
        LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions`
),
-- Step 4: Determine 30-day readmission status.
readmission_status AS (
    SELECT
        ms.subject_id,
        ms.hadm_id,
        ms.medication_complexity_score,
        ms.los_days,
        ms.hospital_expire_flag,
        CASE
            -- Check if there is a next admission within 30 days of the current discharge
            WHEN ana.next_admittime IS NOT NULL
                 AND ana.next_admittime <= TIMESTAMP_ADD(ms.dischtime, INTERVAL 30 DAY)
                 THEN 1
            ELSE 0
        END AS readmitted_30day
    FROM
        medication_scores ms
    LEFT JOIN
        admissions_with_next_adm ana
        ON ms.subject_id = ana.subject_id AND ms.hadm_id = ana.hadm_id
),
-- Step 5: Assign quintiles to each patient admission based on medication complexity score.
ranked_patients AS (
    SELECT
        subject_id,
        hadm_id,
        medication_complexity_score,
        los_days,
        hospital_expire_flag,
        readmitted_30day,
        NTILE(5) OVER (ORDER BY medication_complexity_score ASC) AS complexity_quintile
    FROM
        readmission_status
)
-- Step 6: Final aggregation to compute requested statistics per quintile.
SELECT
    complexity_quintile,
    COUNT(hadm_id) AS n,
    MIN(medication_complexity_score) AS min_medication_complexity_score,
    MAX(medication_complexity_score) AS max_medication_complexity_score,
    ROUND(AVG(medication_complexity_score), 2) AS mean_medication_complexity_score,
    ROUND(AVG(los_days), 2) AS mean_los_days,
    ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_percent,
    ROUND(AVG(readmitted_30day) * 100, 2) AS readmission_30day_percent
FROM
    ranked_patients
GROUP BY
    complexity_quintile
ORDER BY
    complexity_quintile ASC;