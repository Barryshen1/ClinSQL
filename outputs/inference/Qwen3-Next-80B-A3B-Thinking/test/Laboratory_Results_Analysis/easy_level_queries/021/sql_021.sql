WITH male_pneumonia_admissions AS (
    SELECT a.hadm_id, a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
    WHERE p.gender = 'M'
      AND di.long_title LIKE '%pneumonia%'
),
glucose_events AS (
    SELECT 
        l.hadm_id,
        l.charttime,
        l.valuenum
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di ON l.itemid = di.itemid
    WHERE di.label LIKE '%glucose%'
),
latest_glucose AS (
    SELECT 
        mpa.hadm_id,
        ge.valuenum,
        ROW_NUMBER() OVER (PARTITION BY mpa.hadm_id ORDER BY ge.charttime DESC) AS rn
    FROM male_pneumonia_admissions mpa
    JOIN glucose_events ge ON mpa.hadm_id = ge.hadm_id
    WHERE ge.charttime <= mpa.dischtime
)
SELECT 
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY valuenum) AS percentile_75
FROM latest_glucose
WHERE rn = 1;