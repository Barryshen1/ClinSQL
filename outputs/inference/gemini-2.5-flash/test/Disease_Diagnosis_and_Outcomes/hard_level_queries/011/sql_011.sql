with AKI.
   (ICD-9 codes: 584.x; ICD-10 codes: N17.x)
4. Acute Respiratory Distress Syndrome (ARDS) Rate: Percentage of patients in the cohort diagnosed with ARDS.
   (ICD-9 codes: 518.82, 518.5; ICD-10 code: J80)
5. Median Survival of Decedents: The median number of days from admission to death for patients in the cohort who died.
*/
WITH cohort_ami AS (
    -- Main CTE to define the cohort based on age, gender, AMI diagnosis, and ICU stay.
    SELECT
        DISTINCT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.deathtime,
        p.dod, -- Date of death from patients table
        p.gender,
        (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON a.hadm_id = di.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu -- Ensures an ICU stay during this admission
        ON a.hadm_id = icu.hadm_id
    WHERE
        p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 88 AND 98
        AND (
            -- Acute Myocardial Infarction (AMI) ICD codes
            (di.icd_version = 9 AND di.icd_code LIKE '410%') -- ICD-9 for AMI
            OR
            (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%')) -- ICD-10 for AMI
        )
),
cohort_aki_admissions AS (
    -- CTE to identify admissions within the cohort that have an AKI diagnosis
    SELECT DISTINCT
        c.hadm_id
    FROM
        cohort_ami c
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON c.hadm_id = di.hadm_id
    WHERE
        (
            (di.icd_version = 9 AND di.icd_code LIKE '584%') -- AKI ICD-9 codes
            OR
            (di.icd_version = 10 AND di.icd_code LIKE 'N17%') -- AKI ICD-10 codes
        )
),
cohort_ards_admissions AS (
    -- CTE to identify admissions within the cohort that have an ARDS diagnosis
    SELECT DISTINCT
        c.hadm_id
    FROM
        cohort_ami c
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON c.hadm_id = di.hadm_id
    WHERE
        (
            (di.icd_version = 9 AND (di.icd_code = '51882' OR di.icd_code = '5185')) -- ARDS ICD-9 codes (518.82 is most specific)
            OR
            (di.icd_version = 10 AND di.icd_code = 'J80') -- ARDS ICD-10 code
        )
),
cohort_metrics_raw AS (
    -- Aggregate and calculate raw counts for the cohort's metrics
    SELECT
        COUNT(DISTINCT ca.hadm_id) AS total_admissions,
        SUM(CASE
            WHEN
                COALESCE(ca.deathtime, ca.dod) IS NOT NULL
                AND DATE_DIFF(COALESCE(ca.deathtime, ca.dod), ca.admittime, DAY) <= 30
                AND DATE_DIFF(COALESCE(ca.deathtime, ca.dod), ca.admittime, DAY) >= 0 -- Ensure death is not before admission
            THEN 1
            ELSE 0
        END) AS thirty_day_decedents,
        SUM(CASE WHEN aki.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS aki_cases,
        SUM(CASE WHEN ards.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS ards_cases,
        -- Use ARRAY_AGG to collect survival days for median calculation
        ARRAY_AGG(
            DATE_DIFF(COALESCE(ca.deathtime, ca.dod), ca.admittime, DAY)
            -- Only include true decedents with valid survival days for median calculation
            HAVING
                COALESCE(ca.deathtime, ca.dod) IS NOT NULL
                AND DATE_DIFF(COALESCE(ca.deathtime, ca.dod), ca.admittime, DAY) >= 0
        ) AS decedent_survival_days_array
    FROM
        cohort_ami ca
    LEFT JOIN
        cohort_aki_admissions aki
        ON ca.hadm_id = aki.hadm_id
    LEFT JOIN
        cohort_ards_admissions ards
        ON ca.hadm_id = ards.hadm_id
)
SELECT
    -- Average Composite Risk Percentile: This metric typically requires complex calculations from
    -- a variety of physiological measurements to derive severity scores (e.g., APACHE, SAPS),
    -- which are not directly available in standard MIMIC-IV schema as a single percentile.
    -- Thus, a NULL placeholder is provided for this request.
    CAST(NULL AS NUMERIC) AS average_composite_risk_percentile,

    -- 30-day Mortality Rate for the cohort
    ROUND(
        IF(cmr.total_admissions > 0,
            (CAST(cmr.thirty_day_decedents AS NUMERIC) / cmr.total_admissions) * 100,
            0
        ), 2
    ) AS cohort_30_day_mortality_rate_percent,

    -- Acute Kidney Injury (AKI) Rate for the cohort
    ROUND(
        IF(cmr.total_admissions > 0,
            (CAST(cmr.aki_cases AS NUMERIC) / cmr.total_admissions) * 100,
            0
        ), 2
    ) AS cohort_aki_rate_percent,

    -- Acute Respiratory Distress Syndrome (ARDS) Rate for the cohort
    ROUND(
        IF(cmr.total_admissions > 0,
            (CAST(cmr.ards_cases AS NUMERIC) / cmr.total_admissions) * 100,
            0
        ), 2
    ) AS cohort_ards_rate_percent,

    -- Median Survival of Decedents (in days)
    CASE
        WHEN ARRAY_LENGTH(cmr.decedent_survival_days_array) > 0 THEN (
            -- Calculate percentile_cont over the unnested array of survival days
            SELECT
                PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY surv_days) OVER()
            FROM
                UNNEST(cmr.decedent_survival_days_array) AS surv_days
        )
        ELSE NULL -- Return NULL if no decedents in the cohort
    END AS median_survival_decedents_days
FROM
    cohort_metrics_raw cmr;