WITH eligible_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp`.patients
    WHERE gender = 'M'
      AND anchor_age BETWEEN 44 AND 54
),
dialysis_procedures AS (
    SELECT proc.hadm_id, proc.subject_id
    FROM `physionet-data.mimiciv_3_1_hosp`.procedures_icd proc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_procedures d_proc
        ON proc.icd_code = d_proc.icd_code AND proc.icd_version = d_proc.icd_version
    WHERE d_proc.long_title LIKE '%dialysis%'
       OR proc.icd_code IN ('39.95','39.96','39.97')
),
dialysis_admissions AS (
    SELECT DISTINCT a.hadm_id, 
           EXTRACT(DAY FROM a.dischtime - a.admittime) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
    INNER JOIN eligible_patients p ON a.subject_id = p.subject_id
    INNER JOIN dialysis_procedures dp 
        ON a.subject_id = dp.subject_id AND a.hadm_id = dp.hadm_id
    WHERE a.dischtime IS NOT NULL
)
SELECT STDDEV_SAMP(los_days) AS sd_los
FROM dialysis_admissions;