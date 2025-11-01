WITH cohort AS (
    SELECT 
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.deathtime,
        a.hospital_expire_flag,
        -- Approximate age at admission: current admission year minus (anchor_year - anchor_age)
        EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
        p.gender = 'M'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) = 1
),
cabg_procedures AS (
    SELECT DISTINCT
        p.subject_id,
        p.hadm_id,
        p.chartdate  -- Added to make chartdate available
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
        ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    WHERE 
        d.long_title LIKE '%CABG%' 
        OR d.long_title LIKE '%coronary artery bypass graft%'
),
eligible_patients AS (
    SELECT 
        c.subject_id,
        c.hadm_id,
        c.admittime,
        c.dischtime,
        c.deathtime,
        c.hospital_expire_flag,
        c.age_at_admission
    FROM cohort c
    INNER JOIN cabg_procedures cp 
        ON c.subject_id = cp.subject_id AND c.hadm_id = cp.hadm_id
    WHERE 
        c.age_at_admission BETWEEN 48 AND 58
        -- Ensure procedure occurred during the admission
        AND DATE(cp.chartdate) BETWEEN DATE(c.admittime) AND DATE(c.dischtime)
),
death_times AS (
    SELECT 
        subject_id,
        TIMESTAMP_DIFF(deathtime, admittime, HOUR) AS time_to_death_hours
    FROM eligible_patients
    WHERE hospital_expire_flag = 1
)
SELECT 
    APPROX_QUANTILES(time_to_death_hours, 100)[OFFSET(25)] AS p25_time_to_death_hours
FROM death_times;