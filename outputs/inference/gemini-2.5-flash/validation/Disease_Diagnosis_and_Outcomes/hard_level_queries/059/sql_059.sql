WITH AdmissionsFiltered AS (
    -- Base admissions data with age calculation and filtering
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.deathtime AS hosp_deathtime,
        pat.gender,
        pat.dod AS pat_dod,
        pat.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - pat.anchor_year) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON ad.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M'
        -- FIX: Changed 'ADMITTED' to exclude typical non-inpatient admissions, as 'ADMITTED' is not a valid admission_type in MIMIC-IV.
        AND ad.admission_type NOT IN ('OBSERVATION', 'AMBULATORY SURGERY')
        AND (pat.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - pat.anchor_year)) BETWEEN 59 AND 69
),
DKA_HADM_IDS AS (
    -- Identify hadm_ids for DKA patients based on ICD codes
    SELECT DISTINCT di.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    WHERE
        (di.icd_version = 10 AND di.icd_code IN ('E101', 'E111', 'E131')) OR
        (di.icd_version = 9 AND di.icd_code LIKE '2501%') -- For ICD-9, 250.1x
),
AKI_ADMISSIONS AS (
    -- Identify hadm_ids for AKI patients based on ICD codes
    SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 10 AND icd_code LIKE 'N17%') OR -- ICD-10 for Acute Kidney Injury
        (icd_version = 9 AND icd_code IN ('5845', '5846', '5847', '5848', '5849')) -- Specific ICD-9 codes for AKI severity
),
ARDS_ADMISSIONS AS (
    -- Identify hadm_ids for ARDS patients based on ICD codes
    SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 10 AND icd_code LIKE 'J80') OR -- ICD-10 for Acute Respiratory Distress Syndrome (using LIKE J80% to be robust)
        (icd_version = 9 AND icd_code = '51882') -- ICD-9 for Acute Respiratory Distress Syndrome
),
DRG_Mortality_Per_HADM AS (
    -- Ensure one drg_mortality value per hadm_id. Taking MAX if multiple MS-DRGs exist.
    SELECT hadm_id, MAX(drg_mortality) AS drg_mortality
    FROM `physionet-data.mimiciv_3_1_hosp.drgcodes`
    WHERE drg_type = 'MS' -- Focusing on Medicare Severity DRG as a primary risk score
    GROUP BY hadm_id
),
CombinedCohortData AS (
    -- Combine all relevant information for DKA and Control cohorts
    SELECT
        af.hadm_id,
        af.admittime,
        af.dischtime,
        af.hosp_deathtime,
        af.pat_dod,
        drg.drg_mortality,
        CASE WHEN dka.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_dka_patient,
        CASE WHEN aki.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_aki,
        CASE WHEN ards.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_ards,
        (
            (af.hosp_deathtime IS NOT NULL AND af.hosp_deathtime <= af.admittime + INTERVAL '30' DAY) OR
            (af.pat_dod IS NOT NULL AND af.pat_dod <= af.admittime + INTERVAL '30' DAY AND (af.hosp_deathtime IS NULL OR af.hosp_deathtime > af.admittime + INTERVAL '30' DAY))
        ) AS thirty_day_mortality,
        DATETIME_DIFF(af.dischtime, af.admittime, HOUR) / 24.0 AS los_days
    FROM AdmissionsFiltered af
    LEFT JOIN DKA_HADM_IDS dka ON af.hadm_id = dka.hadm_id
    LEFT JOIN DRG_Mortality_Per_HADM drg ON af.hadm_id = drg.hadm_id
    LEFT JOIN AKI_ADMISSIONS aki ON af.hadm_id = aki.hadm_id
    LEFT JOIN ARDS_ADMISSIONS ards ON af.hadm_id = ards.hadm_id
    WHERE drg.drg_mortality IS NOT NULL -- Only include admissions with a valid DRG mortality for analysis
),
AggregatedData AS (
    -- Aggregate metrics for both DKA and Control cohorts
    SELECT
        is_dka_patient,
        COUNT(DISTINCT hadm_id) AS num_admissions,
        AVG(drg_mortality) AS mean_drg_mortality,
        -- FIX: Changed CAST(thirty_day_mortality AS FLOAT64) to CASE WHEN thirty_day_mortality THEN 1 ELSE 0 END
        SUM(CASE WHEN thirty_day_mortality THEN 1 ELSE 0 END) * 100.0 / COUNT(hadm_id) AS thirty_day_mortality_rate_percent,
        SUM(CAST(has_aki AS FLOAT64)) * 100.0 / COUNT(hadm_id) AS aki_rate_percent,
        SUM(CAST(has_ards AS FLOAT64)) * 100.0 / COUNT(hadm_id) AS ards_rate_percent,
        AVG(CASE WHEN NOT thirty_day_mortality THEN los_days ELSE NULL END) AS mean_survivor_los_days -- Only calculate LOS for survivors for the 30 days
    FROM CombinedCohortData
    GROUP BY is_dka_patient
),
DKAMeanMortality AS (
    -- Get the mean DRG mortality for the DKA cohort.
    SELECT mean_drg_mortality
    FROM AggregatedData
    WHERE is_dka_patient = 1
),
ControlMortalityDistribution AS (
    -- Get all individual DRG mortality scores for the Control cohort.
    SELECT drg_mortality
    FROM CombinedCohortData
    WHERE is_dka_patient = 0
    AND drg_mortality IS NOT NULL
)
-- Final selection and presentation of results
SELECT
    CASE WHEN ad.is_dka_patient = 1 THEN 'DKA Cohort' ELSE 'Control Cohort' END AS cohort_type,
    ad.num_admissions,
    ROUND(ad.mean_drg_mortality, 4) AS mean_calculated_risk_score,
    ROUND(ad.thirty_day_mortality_rate_percent, 2) AS thirty_day_mortality_percent,
    ROUND(ad.aki_rate_percent, 2) AS aki_rate_percent,
    ROUND(ad.ards_rate_percent, 2) AS ards_rate_percent,
    ROUND(ad.mean_survivor_los_days, 2) AS mean_survivor_los_days,
    CASE
        WHEN ad.is_dka_patient = 1 THEN NULL -- Percentile calculation is for the DKA mean within the control group
        ELSE (
            SELECT
                ROUND( (
                    SUM(CASE WHEN cmd.drg_mortality <= dmm.mean_drg_mortality THEN 1 ELSE 0 END) * 100.0
                ) / COUNT(cmd.drg_mortality), 2)
            FROM ControlMortalityDistribution cmd, DKAMeanMortality dmm
        )
    END AS dka_mean_mortality_nth_percentile_in_control_group
FROM AggregatedData ad
ORDER BY is_dka_patient DESC; -- Display DKA Cohort first, then Control Cohort;