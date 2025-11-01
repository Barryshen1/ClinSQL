WITH pneumonia_admissions AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id AND adm.subject_id = diag.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 67 AND 77
        AND diag.seq_num = 1  -- primary diagnosis
        AND diag.icd_version = 10
        AND d.icd_code LIKE 'J1[2-8]%'  -- J12 to J18 (pneumonia codes)
        AND adm.dischtime > adm.admittime  -- valid LOS
)
SELECT
    APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS los_25th_percentile
FROM pneumonia_admissions;