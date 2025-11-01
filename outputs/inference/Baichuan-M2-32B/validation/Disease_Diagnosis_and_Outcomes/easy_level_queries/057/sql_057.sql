WITH eligible_patients AS (
    SELECT
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE
        p.gender = 'F'
        AND a.admission_type IN ('Emergency', 'Urgent')  -- Community-acquired indicators
        AND a.admission_location NOT LIKE '%HOSPITAL%'   -- Exclude transfers from other facilities
        AND a.admittime IS NOT NULL
        AND a.dischtime IS NOT NULL
        AND a.dischtime >= a.admittime  -- Valid LOS
        AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 88 AND 98
),
pneumonia_admissions AS (
    SELECT
        ep.subject_id,
        ep.hadm_id,
        ep.admittime,
        ep.dischtime,
        ep.age_at_admission
    FROM eligible_patients ep
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON ep.subject_id = d.subject_id
        AND ep.hadm_id = d.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
    WHERE
        d.seq_num = 1  -- Primary diagnosis
        AND d.icd_version = 10  -- ICD-10
        AND dd.icd_code LIKE 'J12%'  -- Bacterial pneumonia
        OR dd.icd_code LIKE 'J13%'  -- Viral pneumonia
        OR dd.icd_code LIKE 'J15%'  -- Other bacterial pneumonia
        OR dd.icd_code LIKE 'J16%'  -- Other specified pneumonia
        OR dd.icd_code LIKE 'J17%'  -- Aspiration pneumonia
        OR dd.icd_code LIKE 'J18%'  -- Pneumonia, unspecified
        AND dd.long_title LIKE '%pneumonia%'  -- Ensure term matches
)
SELECT
    MIN(DATE_DIFF(CAST(p.dischtime AS DATE), CAST(p.admittime AS DATE), DAY)) AS min_los_days
FROM pneumonia_admissions p;