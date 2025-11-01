WITH eligible_admissions AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        p.gender,
        p.anchor_age,
        p.anchor_year,
        -- Calculate age at admission
        p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON adm.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.subject_id = diag.subject_id 
        AND adm.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code 
        AND diag.icd_version = d.icd_version
    WHERE 
        diag.seq_num = 1  -- Primary diagnosis
        AND (d.long_title LIKE '%ketoacidosis%' 
             OR d.long_title LIKE '%hyperosmolar%')
),
filtered_admissions AS (
    SELECT 
        *,
        -- Calculate LOS in fractional days
        TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0 AS los_days
    FROM eligible_admissions
    WHERE 
        gender = 'M'
        AND age_at_admission BETWEEN 73 AND 83
)
-- Calculate 25th percentile of LOS
SELECT 
    APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS percentile_25
FROM filtered_admissions;