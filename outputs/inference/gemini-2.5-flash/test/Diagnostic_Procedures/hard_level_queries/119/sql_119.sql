WITH ami_codes AS (
    SELECT icd_code
    FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
    WHERE
        (icd_version = 9 AND icd_code LIKE '410%') -- ICD-9 codes for AMI (e.g., 410.0-410.9)
        OR (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%')) -- ICD-10 codes for AMI (e.g., I21.x, I22.x)
),
-- Step 2: Filter for male ICU patients aged 42-52
base_icustays AS (
    SELECT
        p.subject_id,
        p.anchor_age,
        ie.hadm_id,
        ie.stay_id,
        ie.intime
    FROM
        `physionet-data.mimiciv_3_1_hosp`.patients p
    JOIN
        `physionet-data.mimiciv_3_1_icu`.icustays ie
        ON p.subject_id = ie.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 42 AND 52
),
-- Step 3: Identify admissions WITH AMI diagnosis within the base cohort
hadm_with_ami_diagnosis AS (
    SELECT DISTINCT
        bs.subject_id,
        bs.hadm_id
    FROM
        base_icustays bs
    JOIN
        `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
        ON bs.subject_id = di.subject_id AND bs.hadm_id = di.hadm_id
    JOIN
        ami_codes ac
        ON di.icd_code = ac.icd_code
),
-- Step 4: Define the AMI Cohort (ICU stays for patients with AMI in this admission)
ami_cohort AS (
    SELECT
        bs.subject_id,
        bs.hadm_id,
        bs.stay_id,
        bs.intime
    FROM base_icustays bs
    INNER JOIN hadm_with_ami_diagnosis hwa
        ON bs.subject_id = hwa.subject_id AND bs.hadm_id = hwa.hadm_id
),
-- Step 5: Define the Control Cohort (ICU stays for age-matched males without AMI in this admission)
control_cohort AS (
    SELECT
        bs.subject_id,
        bs.hadm_id,
        bs.stay_id,
        bs.intime
    FROM base_icustays bs
    WHERE NOT EXISTS (
        SELECT 1
        FROM hadm_with_ami_diagnosis hwa
        WHERE bs.subject_id = hwa.subject_id
          AND bs.hadm_id = hwa.hadm_id
    )
),
-- Step 6: Calculate diagnostic intensity for AMI cohort (distinct procedures in first ~72 ICU hours)
-- Note: procedures_icd.chartdate is a DATE, not a TIMESTAMP.
-- We approximate "first 72 ICU hours" by including procedures whose chartdate is
-- on the same day as ICU intime, or one or two days after ICU intime.
ami_diagnostic_intensity AS (
    SELECT
        ac.subject_id,
        ac.hadm_id,
        ac.stay_id,
        COUNT(DISTINCT picd.icd_code) AS distinct_procedures_72hr
    FROM
        ami_cohort ac
    JOIN
        `physionet-data.mimiciv_3_1_hosp`.procedures_icd picd
        ON ac.subject_id = picd.subject_id AND ac.hadm_id = picd.hadm_id
    WHERE
        picd.chartdate >= DATE(ac.intime)
        AND picd.chartdate <= DATE_ADD(DATE(ac.intime), INTERVAL 2 DAY)
    GROUP BY
        ac.subject_id,
        ac.hadm_id,
        ac.stay_id
),
-- Step 7: Combine AMI cohort with their diagnostic intensity, handling cases with no procedures (count as 0)
ami_cohort_with_intensity AS (
    SELECT
        ac.subject_id,
        ac.hadm_id,
        ac.stay_id,
        ac.intime,
        COALESCE(adi.distinct_procedures_72hr, 0) AS distinct_procedures_72hr
    FROM
        ami_cohort ac
    LEFT JOIN
        ami_diagnostic_intensity adi
        ON ac.subject_id = adi.subject_id AND ac.hadm_id = adi.hadm_id AND ac.stay_id = adi.stay_id
),
-- Calculate AMI cohort standard aggregates separately
ami_cohort_aggregates AS (
    SELECT
        COUNT(DISTINCT aci.stay_id) AS num_icu_stays,
        AVG(TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0) AS mean_hospital_los_days,
        AVG(CAST(adm.hospital_expire_flag AS BIGNUMERIC)) AS in_hospital_mortality_rate
    FROM
        ami_cohort_with_intensity aci
    JOIN
        `physionet-data.mimiciv_3_1_hosp`.admissions adm
        ON aci.subject_id = adm.subject_id AND aci.hadm_id = adm.hadm_id
),
-- Calculate the 90th percentile for AMI cohort separately
ami_p90_intensity AS (
    SELECT
        PERCENTILE_CONT(distinct_procedures_72hr, 0.9) OVER () AS p90_distinct_procedures_72hr
    FROM
        ami_cohort_with_intensity
    LIMIT 1 -- Ensures a single row for cross join
),
-- Step 8: Combine all statistics for the AMI Cohort
ami_stats AS (
    SELECT
        'AMI Cohort' AS cohort,
        agg.num_icu_stays,
        agg.mean_hospital_los_days,
        agg.in_hospital_mortality_rate,
        p90.p90_distinct_procedures_72hr
    FROM
        ami_cohort_aggregates agg
    CROSS JOIN
        ami_p90_intensity p90
),
-- Step 9: Calculate statistics for the Control Cohort
control_stats AS (
    SELECT
        'Control Cohort' AS cohort,
        COUNT(DISTINCT cc.stay_id) AS num_icu_stays,
        AVG(TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0) AS mean_hospital_los_days,
        AVG(CAST(adm.hospital_expire_flag AS BIGNUMERIC)) AS in_hospital_mortality_rate,
        NULL AS p90_distinct_procedures_72hr -- Not requested for control group
    FROM
        control_cohort cc
    JOIN
        `physionet-data.mimiciv_3_1_hosp`.admissions adm
        ON cc.subject_id = adm.subject_id AND cc.hadm_id = adm.hadm_id
    GROUP BY cohort
)
-- Step 10: Combine results from both cohorts
SELECT * FROM ami_stats
UNION ALL
SELECT * FROM control_stats
ORDER BY cohort;