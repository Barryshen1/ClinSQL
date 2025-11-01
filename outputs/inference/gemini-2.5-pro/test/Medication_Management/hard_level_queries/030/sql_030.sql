WITH
-- Step 1: Find all ICD codes corresponding to "acute pancreatitis"
ap_icd_codes AS (
    SELECT
        icd_code,
        icd_version
    FROM
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE
        LOWER(long_title) LIKE '%acute pancreatitis%'
),

-- Step 2: Identify the primary cohort of hospital admissions
-- Female patients, aged 71-81, with an acute pancreatitis diagnosis.
cohort AS (
    SELECT DISTINCT
        p.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON p.subject_id = adm.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON adm.hadm_id = dx.hadm_id
    INNER JOIN
        ap_icd_codes AS ap
        ON dx.icd_code = ap.icd_code AND dx.icd_version = ap.icd_version
    WHERE
        p.gender = 'F'
        AND (p.anchor_age + EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) BETWEEN 71 AND 81
),

-- Step 3: Calculate medication complexity for each admission in the cohort.
-- Score is defined as the count of unique medications in the first 72 hours.
medication_complexity AS (
    SELECT
        c.subject_id,
        c.hadm_id,
        c.admittime,
        c.dischtime,
        c.hospital_expire_flag,
        COALESCE(COUNT(DISTINCT em.medication), 0) AS medication_complexity_score
    FROM
        cohort AS c
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.emar` AS em
        ON c.hadm_id = em.hadm_id
        -- Filter for medications administered in the first 72 hours of admission
        AND em.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    GROUP BY
        c.subject_id,
        c.hadm_id,
        c.admittime,
        c.dischtime,
        c.hospital_expire_flag
),

-- Step 4: Get all admissions for the subjects in our cohort to check for readmissions.
all_subject_admissions AS (
    SELECT
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        -- Find the next admission time for each patient using a window function
        LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions`
    WHERE
        subject_id IN (SELECT DISTINCT subject_id FROM cohort)
),

-- Step 5: Combine cohort data with calculated outcomes (LOS and 30-day readmission).
cohort_with_outcomes AS (
    SELECT
        mc.hadm_id,
        mc.medication_complexity_score,
        mc.hospital_expire_flag,
        -- Calculate hospital length of stay in fractional days for better accuracy
        DATETIME_DIFF(mc.dischtime, mc.admittime, HOUR) / 24.0 AS los_days,
        -- Flag 1 if a readmission occurred within 30 days of discharge, otherwise 0
        CASE
            WHEN DATETIME_DIFF(asa.next_admittime, mc.dischtime, DAY) BETWEEN 0 AND 30
                THEN 1
            ELSE 0
        END AS readmitted_30_days
    FROM
        medication_complexity AS mc
    LEFT JOIN
        all_subject_admissions AS asa
        ON mc.hadm_id = asa.hadm_id
),

-- Step 6: Stratify the cohort into tertiles based on medication complexity score.
cohort_with_tertiles AS (
    SELECT
        *,
        NTILE(3) OVER (ORDER BY medication_complexity_score) AS score_tertile
    FROM
        cohort_with_outcomes
)

-- Step 7: Final aggregation to report outcomes per tertile.
SELECT
    score_tertile,
    COUNT(hadm_id) AS number_of_admissions,
    MIN(medication_complexity_score) AS min_med_score_in_tertile,
    MAX(medication_complexity_score) AS max_med_score_in_tertile,
    ROUND(AVG(los_days), 2) AS avg_los_days,
    ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_rate_pct,
    ROUND(AVG(readmitted_30_days) * 100, 2) AS readmission_30_day_rate_pct
FROM
    cohort_with_tertiles
GROUP BY
    score_tertile
ORDER BY
    score_tertile;