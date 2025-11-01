SELECT
    STDDEV(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0) AS std_dev_los_days
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON adm.subject_id = p.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dia
    ON adm.subject_id = dia.subject_id AND adm.hadm_id = dia.hadm_id
WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND dia.seq_num = 1 -- Primary diagnosis
    AND (
        (dia.icd_version = 9 AND (dia.icd_code = '99592' OR dia.icd_code = '78552')) -- ICD-9: Severe Sepsis or Septic Shock
        OR
        (dia.icd_version = 10 AND dia.icd_code LIKE 'R652%') -- ICD-10: Severe Sepsis or Septic Shock (R65.20, R65.21)
    )
    AND adm.dischtime IS NOT NULL -- Ensure discharge time exists for LOS calculation
    AND adm.admittime IS NOT NULL -- Ensure admit time exists for LOS calculation
    AND DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) >= 0; -- Ensure valid LOS (discharge after admission);