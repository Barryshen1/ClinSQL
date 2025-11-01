WITH TargetCohortAdmissions AS (
    SELECT DISTINCT
        adm.hadm_id,
        adm.subject_id,
        adm.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON pa.subject_id = adm.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON adm.hadm_id = di.hadm_id
    WHERE
        pa.gender = 'F'
        AND pa.anchor_age = 45 -- Age at anchor_year, suitable for age cohort
        AND (
            -- ICD-10 codes for Gastrointestinal hemorrhage
            di.icd_code LIKE 'K920%' -- Hematemesis
            OR di.icd_code LIKE 'K921%' -- Melena
            OR di.icd_code LIKE 'K922%' -- Gastrointestinal hemorrhage, unspecified
        )
),
DischargeDayHemoglobin AS (
    SELECT
        tca.hadm_id,
        le.valuenum AS hemoglobin_value,
        le.charttime
    FROM
        TargetCohortAdmissions tca
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON tca.subject_id = le.subject_id AND tca.hadm_id = le.hadm_id
    WHERE
        le.itemid = 51221 -- Hemoglobin (identified from d_labitems)
        AND le.valueuom = 'g/dL' -- Ensure correct units
        AND DATE(le.charttime) = DATE(tca.dischtime) -- On discharge day
        AND le.valuenum IS NOT NULL
        AND le.valuenum > 0 -- Exclude invalid/non-positive hemoglobin values
),
LatestDischargeDayHemoglobin AS (
    SELECT
        hadm_id,
        hemoglobin_value
    FROM
        DischargeDayHemoglobin
    QUALIFY ROW_NUMBER() OVER(PARTITION BY hadm_id ORDER BY charttime DESC, hemoglobin_value DESC) = 1
    -- Selects the latest hemoglobin reading on the discharge day for each admission.
    -- Ties on charttime are broken by taking the highest hemoglobin_value.
)
SELECT
    PERCENTILE_CONT(hemoglobin_value, 0.75) AS p75_discharge_hemoglobin_g_dL
FROM
    LatestDischargeDayHemoglobin;