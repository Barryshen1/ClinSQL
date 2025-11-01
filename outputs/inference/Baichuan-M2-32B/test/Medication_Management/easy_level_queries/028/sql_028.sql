WITH patients_admissions AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON p.subject_id = a.subject_id
    WHERE 
        p.gender = 'F' 
        AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 44 AND 54
),
dapt_admissions AS (
    SELECT 
        pa.subject_id,
        pa.hadm_id,
        pa.admittime,
        pa.dischtime,
        pa.age_at_admission
    FROM patients_admissions pa
    INNER JOIN (
        SELECT 
            pr.subject_id,
            pr.hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        WHERE 
            pr.drug IN ('aspirin', 'clopidogrel', 'ticagrelor', 'prasugrel')
            AND pr.starttime IS NOT NULL
        GROUP BY pr.subject_id, pr.hadm_id
        HAVING COUNT(DISTINCT pr.drug) >= 2
    ) dapt ON pa.subject_id = dapt.subject_id AND pa.hadm_id = dapt.hadm_id
),
antiplatelet_prescriptions AS (
    SELECT 
        dapt.subject_id,
        dapt.hadm_id,
        pr.drug,
        pr.starttime,
        pr.stoptime,
        TIMESTAMP_DIFF(
            COALESCE(pr.stoptime, dapt.dischtime), 
            pr.starttime, 
            DAY
        ) AS prescription_duration_days
    FROM dapt_admissions dapt
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        ON dapt.subject_id = pr.subject_id
        AND dapt.hadm_id = pr.hadm_id
    WHERE 
        pr.drug IN ('aspirin', 'clopidogrel', 'ticagrelor', 'prasugrel')
        AND pr.starttime <= dapt.dischtime
        AND (pr.stoptime >= dapt.admittime OR pr.stoptime IS NULL)
        AND COALESCE(pr.stoptime, dapt.dischtime) >= pr.starttime
)
SELECT 
    STDDEV_SAMP(prescription_duration_days) AS sd_prescription_duration
FROM antiplatelet_prescriptions;