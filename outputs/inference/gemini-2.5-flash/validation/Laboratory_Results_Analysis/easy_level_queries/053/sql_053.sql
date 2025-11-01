WITH IschemicStrokeAdmissions AS (
    SELECT DISTINCT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON pa.subject_id = ad.subject_id
    JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ad.subject_id = di.subject_id AND ad.hadm_id = di.hadm_id
    WHERE
        pa.gender = 'F'
        AND pa.anchor_age = 82 -- Filter for 82-year-old
        AND (
            (di.icd_version = 9 AND di.icd_code LIKE '434%') -- ICD-9 for ischemic stroke
            OR
            (di.icd_version = 10 AND di.icd_code LIKE 'I63%') -- ICD-10 for ischemic stroke
        )
),
EarliestAdmissionGlucose AS (
    SELECT
        sa.hadm_id,
        le.valuenum,
        ROW_NUMBER() OVER (PARTITION BY sa.hadm_id ORDER BY le.charttime) AS rn
    FROM
        IschemicStrokeAdmissions sa
    JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON sa.subject_id = le.subject_id AND sa.hadm_id = le.hadm_id
    WHERE
        le.itemid = 50931 -- Itemid for 'Glucose' (from d_labitems: label='Glucose', fluid='Ser/Plas')
        AND le.valuenum IS NOT NULL
        AND le.charttime >= sa.admittime
        AND le.charttime <= DATETIME_ADD(sa.admittime, INTERVAL 24 HOUR) -- Glucose measured within 24 hours of admission
)
SELECT
    PERCENTILE_CONT(ag.valuenum, 0.75) OVER() AS p75_admission_glucose_mg_dl
FROM
    EarliestAdmissionGlucose ag
WHERE
    ag.rn = 1; -- Select only the earliest glucose measurement for each admission;