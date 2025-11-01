WITH pneumonia_males AS (
    SELECT DISTINCT adm.subject_id, adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    WHERE pat.gender = 'M'
        AND pat.anchor_age >= 18
        AND d.long_title LIKE '%pneumonia%'
),
creatinine_nadir AS (
    SELECT pm.hadm_id,
        MIN(le.valuenum) AS nadir_creatinine
    FROM pneumonia_males pm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON pm.hadm_id = adm.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON pm.hadm_id = le.hadm_id AND pm.subject_id = le.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
    WHERE dli.itemid = 50912  -- Serum creatinine
        AND le.valuenum IS NOT NULL
        AND le.charttime BETWEEN adm.admittime AND adm.dischtime
    GROUP BY pm.hadm_id
)
SELECT 
    APPROX_QUANTILES(nadir_creatinine, 100)[OFFSET(25)] AS q25,
    APPROX_QUANTILES(nadir_creatinine, 100)[OFFSET(75)] AS q75,
    APPROX_QUANTILES(nadir_creatinine, 100)[OFFSET(75)] - APPROX_QUANTILES(nadir_creatinine, 100)[OFFSET(25)] AS iqr
FROM creatinine_nadir;