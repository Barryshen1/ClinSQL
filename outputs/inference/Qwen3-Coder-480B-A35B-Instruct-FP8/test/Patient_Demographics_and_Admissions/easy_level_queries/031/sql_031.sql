WITH hf_admissions AS (
    -- Get all admissions with a primary diagnosis of heart failure
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.deathtime,
        p.anchor_age,
        p.gender
    FROM
        physionet-data.mimiciv_3_1_hosp.admissions a
    JOIN
        physionet-data.mimiciv_3_1_hosp.patients p
        ON a.subject_id = p.subject_id
    JOIN
        physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
        ON a.hadm_id = d.hadm_id
    JOIN
        physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE
        d.seq_num = 1
        AND LOWER(dd.long_title) LIKE '%heart failure%'
        AND p.gender = 'F'
        AND p.anchor_age BETWEEN 38 AND 48
        AND a.deathtime IS NULL -- exclude in-hospital deaths
),
first_hf_admissions AS (
    -- Get only the first HF admission per patient
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM
        hf_admissions
),
indexed_admissions AS (
    -- Add next admission time for readmission check
    SELECT
        *,
        LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
    FROM
        first_hf_admissions
    WHERE
        rn = 1
),
readmission_flag AS (
    -- Determine if readmission occurred within 30 days
    SELECT
        *,
        CASE
            WHEN next_admittime IS NOT NULL
                 AND DATETIME_DIFF(next_admittime, dischtime, DAY) <= 30
            THEN 1
            ELSE 0
        END AS readmitted_30_days
    FROM
        indexed_admissions
)
-- Final readmission rate
SELECT
    AVG(readmitted_30_days) AS avg_30_day_readmission_rate
FROM
    readmission_flag;