WITH pneumonia_admissions AS (
    SELECT DISTINCT d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
    WHERE 
        (d.icd_version = 10 AND di.icd_code LIKE 'J18%') OR
        (d.icd_version = 9 AND di.icd_code BETWEEN '480' AND '486')
)
SELECT 
    APPROX_QUANTILES(los, 100)[OFFSET(25)] AS los_25th_percentile
FROM (
    SELECT 
        a.hadm_id,
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    INNER JOIN pneumonia_admissions pa
        ON a.hadm_id = pa.hadm_id
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 49 AND 59
        AND a.dischtime IS NOT NULL  -- exclude ongoing admissions
);