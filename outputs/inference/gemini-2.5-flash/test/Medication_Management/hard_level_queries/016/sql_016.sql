WITH Cohort AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 80 AND 90
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE di.subject_id = ad.subject_id AND di.hadm_id = ad.hadm_id
              AND (
                    (di.icd_version = 10 AND di.icd_code LIKE 'K72%') -- ICD-10 codes for hepatic failure
                    OR (di.icd_version = 9 AND (di.icd_code = '570' OR di.icd_code = '5722')) -- ICD-9 codes (572.2 stored as 5722)
                  )
        )
),
-- Calculate medication complexity score for each admission in the cohort
-- Score is defined as the number of unique drugs prescribed within the first 7 days of admission
MedComplexity AS (
    SELECT
        c.subject_id,
        c.hadm_id,
        c.admittime,
        c.dischtime,
        c.hospital_expire_flag,
        DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
        -- Count distinct drugs within 7 days of admission_time.
        -- COALESCE handles admissions with no prescriptions in the first 7 days by assigning a score of 0.
        COALESCE(COUNT(DISTINCT p_rx.drug), 0) AS medication_complexity_score
    FROM
        Cohort c
    LEFT JOIN -- Use LEFT JOIN to include all cohort admissions, even if no prescriptions found
        `physionet-data.mimiciv_3_1_hosp.prescriptions` p_rx
        ON c.subject_id = p_rx.subject_id
        AND c.hadm_id = p_rx.hadm_id
        AND p_rx.starttime >= c.admittime
        AND p_rx.starttime <= DATETIME_ADD(c.admittime, INTERVAL 7 DAY)
    GROUP BY
        c.subject_id,
        c.hadm_id,
        c.admittime,
        c.dischtime,
        c.hospital_expire_flag
),
-- Determine 30-day readmission status for each admission
ReadmissionCheck AS (
    SELECT
        mc.*,
        CASE
            -- A 30-day readmission is counted if the patient was discharged alive (hospital_expire_flag = 0)
            -- AND had another admission for the same subject_id within 30 days of discharge.
            WHEN mc.hospital_expire_flag = 0 AND EXISTS (
                SELECT 1
                FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm_next
                WHERE adm_next.subject_id = mc.subject_id
                  AND adm_next.admittime > mc.dischtime -- Must be a subsequent admission
                  AND DATETIME_DIFF(adm_next.admittime, mc.dischtime, DAY) <= 30
                  -- To strictly count readmissions for the *same* patient, check for the same subject_id.
                  -- The original query implicitly handles this by joining on subject_id.
            ) THEN 1
            ELSE 0
        END AS readmitted_30day
    FROM MedComplexity mc
),
-- Assign complexity tertiles based on the medication complexity score
Tertiles AS (
    SELECT
        rc.*,
        NTILE(3) OVER (ORDER BY rc.medication_complexity_score ASC) AS complexity_tertile
    FROM
        ReadmissionCheck rc
)
-- Final aggregation to report the required metrics per tertile
SELECT
    complexity_tertile,
    COUNT(DISTINCT hadm_id) AS cohort_size_per_tertile,
    -- Average Length of Stay in days
    AVG(los_days) AS average_los_days,
    -- In-hospital mortality rate as a percentage
    SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(hadm_id)) * 100 AS in_hospital_mortality_rate,
    -- 30-day readmission rate as a percentage
    SAFE_DIVIDE(SUM(readmitted_30day), COUNT(hadm_id)) * 100 AS readmission_30day_rate
FROM
    Tertiles
GROUP BY
    complexity_tertile
ORDER BY
    complexity_tertile;