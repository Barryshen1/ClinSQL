WITH cohort AS (
    SELECT 
        p.subject_id, 
        p.gender, 
        p.anchor_age,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        -- Calculate length of stay in days
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        -- Get the first Troponin T measurement per admission
        FIRST_VALUE(l.valuenum) OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS first_troponin_t,
        FIRST_VALUE(l.ref_range_upper) OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS ref_upper,
        FIRST_VALUE(l.flag) OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
        ON a.hadm_id = l.hadm_id AND a.subject_id = l.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
        ON l.itemid = dl.itemid
    WHERE 
        p.anchor_age BETWEEN 73 AND 83
        AND p.gender = 'M'
        AND d.seq_num = 1  -- primary diagnosis
        AND d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' OR d.icd_code LIKE 'I24%'  -- ACS codes
        AND dl.label LIKE 'Troponin T'  -- Identify Troponin T lab
),
filtered_cohort AS (
    SELECT 
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        los_days,
        hospital_expire_flag,
        first_troponin_t,
        ref_upper,
        flag
    FROM cohort
    WHERE 
        -- Check if the first Troponin T is elevated: either above upper reference or flagged abnormal
        (first_troponin_t > ref_upper OR flag = 'abnormal')
    QUALIFY ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY admittime) = 1  -- Ensure one row per admission
)
SELECT 
    COUNT(*) AS num_patients,
    AVG(los_days) AS avg_los_days,
    SUM(hospital_expire_flag) AS in_hospital_deaths,
    ROUND(SUM(hospital_expire_flag) / COUNT(*) * 100, 2) AS mortality_percent
FROM filtered_cohort;