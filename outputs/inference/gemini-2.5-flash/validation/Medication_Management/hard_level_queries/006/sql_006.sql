WITH icu_cohort_base AS (
    SELECT
        p.subject_id,
        adm.hadm_id,
        CAST(p.anchor_age AS INT64) AS age, -- Ensure age is integer
        p.gender,
        icu.stay_id,
        icu.intime AS icu_intime,
        icu.outtime AS icu_outtime,
        icu.los AS icu_los_days, -- ICU LOS is in days
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.hadm_id = icu.hadm_id AND adm.subject_id = icu.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 37 AND 47
),
-- Step 2: Calculate distinct medications within the first 72 hours of ICU stay
medication_counts AS (
    SELECT
        ich.subject_id,
        ich.hadm_id,
        ich.stay_id,
        COUNT(DISTINCT pr.drug) AS distinct_meds_72hr
    FROM
        icu_cohort_base ich
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        ON ich.subject_id = pr.subject_id AND ich.hadm_id = pr.hadm_id
    WHERE
        pr.starttime BETWEEN ich.icu_intime AND DATETIME_ADD(ich.icu_intime, INTERVAL 72 HOUR)
    GROUP BY
        ich.subject_id, ich.hadm_id, ich.stay_id
),
-- Step 3: Combine base ICU cohort with medication counts and convert LOS to hours
icu_cohort_with_meds AS (
    SELECT
        ich.subject_id,
        ich.hadm_id,
        ich.stay_id,
        ich.age,
        ich.gender,
        ich.admittime,
        ich.dischtime,
        ich.icu_intime,
        ich.icu_outtime,
        ich.icu_los_days * 24 AS icu_los_hours, -- Convert ICU LOS from days to hours
        ich.hospital_expire_flag,
        COALESCE(mc.distinct_meds_72hr, 0) AS distinct_meds_72hr -- Handle cases with no prescriptions in 72h
    FROM
        icu_cohort_base ich
    LEFT JOIN
        medication_counts mc
        ON ich.stay_id = mc.stay_id
),
-- Step 4: Calculate 30-day readmission status for each admission in the cohort
readmission_data AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        a.dischtime,
        LEAD(a.admittime) OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS next_admittime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` a
),
readmission_flags AS (
    SELECT
        rd.subject_id,
        rd.hadm_id,
        CASE
            WHEN rd.next_admittime IS NOT NULL
             AND DATETIME_DIFF(rd.next_admittime, rd.dischtime, DAY) <= 30
            THEN 1
            ELSE 0
        END AS readmitted_30day
    FROM
        readmission_data rd
),
-- Step 5: Combine all data for stratification and outcome calculation
full_cohort_data AS (
    SELECT
        icm.subject_id,
        icm.hadm_id,
        icm.stay_id,
        icm.age,
        icm.gender,
        icm.icu_los_hours,
        icm.hospital_expire_flag,
        icm.distinct_meds_72hr,
        rf.readmitted_30day
    FROM
        icu_cohort_with_meds icm
    INNER JOIN
        readmission_flags rf
        ON icm.subject_id = rf.subject_id AND icm.hadm_id = rf.hadm_id
),
-- Step 6: Assign medication complexity quintiles
ranked_cohort AS (
    SELECT
        *,
        NTILE(5) OVER (ORDER BY distinct_meds_72hr) AS medication_complexity_quintile
    FROM
        full_cohort_data
),
-- Step 7: Calculate outcomes per quintile
quintile_statistics AS (
    SELECT
        medication_complexity_quintile,
        COUNT(DISTINCT stay_id) AS num_icu_stays,
        ROUND(AVG(icu_los_hours), 2) AS avg_icu_los_hours,
        -- In-hospital mortality is tied to the hospital admission from which the ICU stay occurred.
        -- Denominator is the number of ICU stays in the quintile.
        ROUND(SUM(CAST(hospital_expire_flag AS BIGNUMERIC)) * 100.0 / COUNT(DISTINCT stay_id), 2) AS in_hospital_mortality_rate_percent,
        -- 30-day readmission is an admission-level outcome.
        -- Denominator is the number of distinct hospital admissions associated with ICU stays in the quintile.
        ROUND(SUM(CAST(readmitted_30day AS BIGNUMERIC)) * 100.0 / COUNT(DISTINCT hadm_id), 2) AS readmission_30day_rate_percent
    FROM
        ranked_cohort
    GROUP BY
        medication_complexity_quintile
    ORDER BY
        medication_complexity_quintile
),
-- Step 8: Identify a representative medication complexity for a 42-year-old male
-- We calculate the median distinct meds count for all 42-year-old males in the cohort.
representative_42yo_meds AS (
    SELECT
        PERCENTILE_CONT(distinct_meds_72hr, 0.5) OVER () AS median_distinct_meds
    FROM
        full_cohort_data
    WHERE
        age = 42
),
-- Step 9: Determine which quintile the representative 42-year-old (with median meds) falls into
patient_quintile AS (
    SELECT
        sq.medication_complexity_quintile
    FROM (
        SELECT
            medication_complexity_quintile,
            MIN(distinct_meds_72hr) AS min_meds_in_quintile,
            MAX(distinct_meds_72hr) AS max_meds_in_quintile
        FROM ranked_cohort
        GROUP BY medication_complexity_quintile
    ) AS sq, representative_42yo_meds r
    WHERE
        -- The median could be an float, check against the min/max integer bounds of quintile
        FLOOR(r.median_distinct_meds) >= sq.min_meds_in_quintile
        AND FLOOR(r.median_distinct_meds) <= sq.max_meds_in_quintile
    ORDER BY medication_complexity_quintile -- If median falls exactly on a boundary, pick the lower quintile by MIN or higher by MAX
    LIMIT 1 -- Ensure only one quintile is selected
)
-- Final SELECT statements: first for quintile statistics, then for specific patient risk
SELECT
    'Quintile Statistics' AS section,
    CAST(qs.medication_complexity_quintile AS STRING) AS category,
    qs.num_icu_stays,
    qs.avg_icu_los_hours,
    qs.in_hospital_mortality_rate_percent,
    qs.readmission_30day_rate_percent
FROM
    quintile_statistics qs

UNION ALL

SELECT
    'Risk Estimation for 42-year-old Man' AS section,
    CONCAT('Falls into Quintile ', CAST(pq.medication_complexity_quintile AS STRING)) AS category,
    NULL AS num_icu_stays, -- Not applicable for single patient estimation
    qs_patient.avg_icu_los_hours,
    qs_patient.in_hospital_mortality_rate_percent,
    qs_patient.readmission_30day_rate_percent
FROM
    patient_quintile pq
INNER JOIN
    quintile_statistics qs_patient
    ON pq.medication_complexity_quintile = qs_patient.medication_complexity_quintile;