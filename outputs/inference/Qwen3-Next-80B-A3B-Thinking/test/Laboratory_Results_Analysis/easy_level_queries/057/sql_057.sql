WITH pneumonia_patients AS (
    SELECT DISTINCT
        a.hadm_id,
        a.admittime,
        a.dischtime,
        p.gender
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE p.gender = 'M'
      AND p.anchor_age = 61
      AND LOWER(dd.long_title) LIKE '%pneumonia%'
),
nadir_creatinine AS (
    SELECT
        pp.hadm_id,
        MIN(l.valuenum) AS nadir_creat
    FROM pneumonia_patients pp
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON pp.hadm_id = l.hadm_id
    WHERE l.itemid = 50912
      AND l.valuenum IS NOT NULL
      AND l.charttime BETWEEN pp.admittime AND pp.dischtime
    GROUP BY pp.hadm_id
)
SELECT
    APPROX_QUANTILES(nadir_creat, 4)[OFFSET(1)] AS q1,
    APPROX_QUANTILES(nadir_creat, 4)[OFFSET(3)] AS q3,
    APPROX_QUANTILES(nadir_creat, 4)[OFFSET(3)] - APPROX_QUANTILES(nadir_creat, 4)[OFFSET(1)] AS iqr
FROM nadir_creatinine;