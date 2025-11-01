WITH acs_admissions AS (
    SELECT DISTINCT diag.subject_id, diag.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    WHERE d.long_title LIKE 'Acute coronary syndrome%'
        OR d.long_title LIKE 'Unstable angina%'
        OR d.long_title LIKE 'Myocardial infarction%'
),
female_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F'
),
troponin_labs AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
    WHERE label LIKE '%troponin%' AND fluid = 'Blood'
),
nadir_troponin_per_admission AS (
    SELECT
        le.hadm_id,
        MIN(le.valuenum) AS nadir_troponin
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN acs_admissions aa
        ON le.hadm_id = aa.hadm_id
    INNER JOIN female_patients fp
        ON le.subject_id = fp.subject_id
    INNER JOIN troponin_labs tl
        ON le.itemid = tl.itemid
    WHERE le.valuenum IS NOT NULL
        AND le.hadm_id IS NOT NULL
    GROUP BY le.hadm_id
)
SELECT
    PERCENTILE_CONT(nadir_troponin, 0.25) OVER() AS percentile_25
FROM nadir_troponin_per_admission
LIMIT 1;