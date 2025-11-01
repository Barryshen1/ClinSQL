WITH IschemicStrokeMaleGlucose AS (
    SELECT
        le.valuenum AS serum_glucose_value
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dicd
        ON adm.subject_id = dicd.subject_id AND adm.hadm_id = dicd.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON adm.subject_id = le.subject_id AND adm.hadm_id = le.hadm_id
    WHERE
        p.gender = 'M'
        -- Filter for ischemic stroke (ICD-10 codes starting with I63)
        AND dicd.icd_code LIKE 'I63%'
        AND dicd.icd_version = 10
        -- Filter for 'Glucose, serum' lab test (itemid 50931)
        AND le.itemid = 50931 -- Common itemid for 'Glucose, serum'
        -- Filter for lab events occurring on the discharge day
        AND DATE(le.charttime) = DATE(adm.dischtime)
        -- Ensure the lab value is numeric and not null
        AND le.valuenum IS NOT NULL
)
SELECT
    PERCENTILE_CONT(serum_glucose_value, 0.75) OVER() - PERCENTILE_CONT(serum_glucose_value, 0.25) OVER() AS iqr_serum_glucose
FROM
    IschemicStrokeMaleGlucose
LIMIT 1;