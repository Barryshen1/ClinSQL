WITH male_icu_patients AS (
    SELECT DISTINCT p.subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON p.subject_id = icu.subject_id
    WHERE p.gender = 'M'
),
potassium_labs AS (
    SELECT le.valuenum
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
    INNER JOIN male_icu_patients mip
        ON le.subject_id = mip.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON le.hadm_id = adm.hadm_id
    WHERE dli.itemid = 50971  -- Serum potassium
        AND le.valuenum IS NOT NULL
        AND DATE(le.charttime) = DATE(adm.dischtime)
)
SELECT
    PERCENTILE_CONT(valuenum, 0.75) OVER() AS potassium_75th_percentile
FROM potassium_labs
LIMIT 1;