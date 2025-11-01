WITH pneumonia_admissions AS (
    SELECT a.hadm_id, a.admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
    WHERE p.gender = 'M'
      AND LOWER(di.long_title) LIKE '%pneumonia%'
),
glucose_means AS (
    SELECT pa.hadm_id, AVG(l.valuenum) AS mean_glucose
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di 
        ON l.itemid = di.itemid
    JOIN pneumonia_admissions pa ON l.hadm_id = pa.hadm_id
    WHERE LOWER(di.label) LIKE '%glucose%'
      AND l.charttime BETWEEN pa.admittime AND pa.admittime + INTERVAL 24 HOUR
      AND l.valuenum IS NOT NULL
    GROUP BY pa.hadm_id
)
SELECT PERCENTILE_CONT(mean_glucose, 0.75) AS percentile_75
FROM glucose_means;