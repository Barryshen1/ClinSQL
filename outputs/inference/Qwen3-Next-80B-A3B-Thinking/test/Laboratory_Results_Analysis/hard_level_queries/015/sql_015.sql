WITH target_patients AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        p.anchor_age,
        p.anchor_year,
        EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
        AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 49 AND 59
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag 
                ON d.icd_code = d_diag.icd_code AND d.icd_version = d_diag.icd_version
            WHERE d.subject_id = a.subject_id 
                AND d.hadm_id = a.hadm_id
                AND (d_diag.long_title LIKE '%ischemic stroke%' OR d.icd_code LIKE 'I63%')
        )
),

lab_events AS (
    SELECT 
        l.subject_id,
        l.hadm_id,
        l.charttime,
        l.valuenum,
        d_lab.ref_range_lower,
        d_lab.ref_range_upper,
        CASE 
            WHEN d_lab.ref_range_lower IS NOT NULL AND d_lab.ref_range_upper IS NOT NULL 
                AND (l.valuenum < d_lab.ref_range_lower OR l.valuenum > d_lab.ref_range_upper) 
            THEN 1 
            ELSE 0 
        END AS is_abnormal
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d_lab 
        ON l.itemid = d_lab.itemid
    WHERE l.valuenum IS NOT NULL
),

lab_scores AS (
    SELECT 
        tp.subject_id,
        tp.hadm_id,
        SUM(CASE WHEN le.charttime BETWEEN tp.admittime AND tp.admittime + INTERVAL 72 HOUR THEN le.is_abnormal ELSE 0 END) AS lab_instability_score
    FROM target_patients tp
    LEFT JOIN lab_events le 
        ON tp.subject_id = le.subject_id AND tp.hadm_id = le.hadm_id
    GROUP BY tp.subject_id, tp.hadm_id
),

percentile_75 AS (
    SELECT 
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY lab_instability_score) AS p75
    FROM lab_scores
),

control_patients AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        p.anchor_age,
        p.anchor_year,
        EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
        AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 49 AND 59
        AND NOT EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag 
                ON d.icd_code = d_diag.icd_code AND d.icd_version = d_diag.icd_version
            WHERE d.subject_id = a.subject_id 
                AND d.hadm_id = a.hadm_id
                AND (d_diag.long_title LIKE '%ischemic stroke%' OR d.icd_code LIKE 'I63%')
        )
),

control_lab_scores AS (
    SELECT 
        cp.subject_id,
        cp.hadm_id,
        SUM(CASE WHEN le.charttime BETWEEN cp.admittime AND cp.admittime + INTERVAL 72 HOUR THEN le.is_abnormal ELSE 0 END) AS lab_instability_score
    FROM control_patients cp
    LEFT JOIN lab_events le 
        ON cp.subject_id = le.subject_id AND cp.hadm_id = le.hadm_id
    GROUP BY cp.subject_id, cp.hadm_id
),

high_instability AS (
    SELECT 
        ls.subject_id,
        ls.hadm_id,
        ls.lab_instability_score,
        a.dischtime,
        a.admittime,
        a.hospital_expire_flag
    FROM lab_scores ls
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON ls.subject_id = a.subject_id AND ls.hadm_id = a.hadm_id
    CROSS JOIN percentile_75 p
    WHERE ls.lab_instability_score >= p.p75
),

high_instability_stats AS (
    SELECT 
        AVG(DATE_DIFF(dischtime, admittime, DAY)) AS avg_los,
        AVG(hospital_expire_flag) AS mortality_rate,
        AVG(lab_instability_score) AS avg_lab_score_high
    FROM high_instability
),

control_stats AS (
    SELECT 
        AVG(lab_instability_score) AS avg_lab_score_control
    FROM control_lab_scores
)

SELECT 
    p.p75,
    h.avg_los,
    h.mortality_rate,
    h.avg_lab_score_high,
    c.avg_lab_score_control
FROM percentile_75 p
CROSS JOIN high_instability_stats h
CROSS JOIN control_stats c;