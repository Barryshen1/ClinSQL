with Heart Failure diagnosis) and compares the most unstable quartile of this cohort to the general ICU population on several metrics. */
WITH cohort_base AS (
    SELECT
        p.subject_id,
        adm.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.outtime,
        adm.hospital_expire_flag,
        DATETIME_DIFF(icu.outtime, icu.intime, HOUR) / 24.0 AS icu_los_days,
        -- Calculate age at admission based on anchor year logic
        p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.hadm_id = icu.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_icd
        ON adm.hadm_id = diag_icd.hadm_id
    WHERE
        p.gender = 'M'
        AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 45 AND 55 -- Age range
        -- Heart Failure diagnosis (ICD-9: 428.xx, ICD-10: I50.xx)
        AND (LEFT(diag_icd.icd_code, 3) = '428' OR LEFT(diag_icd.icd_code, 3) = 'I50')
),
-- Step 2: Define the general ICU population (all ICU stays for comparison)
all_icu_base AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.outtime,
        adm.hospital_expire_flag,
        DATETIME_DIFF(icu.outtime, icu.intime, HOUR) / 24.0 AS icu_los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.hadm_id = icu.hadm_id
),
-- Step 3: Extract relevant vital signs from chartevents for all ICU stays within the first 72 hours
vitals_72hr AS (
    SELECT
        ce.stay_id,
        ce.charttime,
        ce.itemid,
        ce.valuenum
    FROM
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN
        all_icu_base aib
        ON ce.stay_id = aib.stay_id
    WHERE
        ce.charttime BETWEEN aib.intime AND DATETIME_ADD(aib.intime, INTERVAL 72 HOUR)
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum >= 0 -- Exclude nonsensical negative values
        -- Filter for relevant vital sign itemids only
        AND ce.itemid IN (
            211, 220045, -- Heart Rate
            442, 456, 220052, 220092, 220181, -- Mean Arterial Pressure (MAP)
            618, 220210 -- Respiratory Rate
        )
),
-- Step 4: Calculate composite instability score and individual condition counts for all ICU stays
-- Using COALESCE(SUM(...), 0) to handle stays with no relevant vital events in the first 72h
instability_scores_all_icu AS (
    SELECT
        aib.subject_id,
        aib.hadm_id,
        aib.stay_id,
        -- Count of tachycardia events (HR > 100)
        COALESCE(SUM(CASE WHEN v72.itemid IN (211, 220045) AND v72.valuenum > 100 THEN 1 ELSE 0 END), 0) AS hr_unstable_cnt,
        -- Count of hypotension events (MAP < 65)
        COALESCE(SUM(CASE WHEN v72.itemid IN (442, 456, 220052, 220092, 220181) AND v72.valuenum < 65 THEN 1 ELSE 0 END), 0) AS map_unstable_cnt,
        -- Count of tachypnea events (RR > 20)
        COALESCE(SUM(CASE WHEN v72.itemid IN (618, 220210) AND v72.valuenum > 20 THEN 1 ELSE 0 END), 0) AS rr_unstable_cnt,
        -- Composite score is the sum of these unstable counts
        (COALESCE(SUM(CASE WHEN v72.itemid IN (211, 220045) AND v72.valuenum > 100 THEN 1 ELSE 0 END), 0) +
         COALESCE(SUM(CASE WHEN v72.itemid IN (442, 456, 220052, 220092, 220181) AND v72.valuenum < 65 THEN 1 ELSE 0 END), 0) +
         COALESCE(SUM(CASE WHEN v72.itemid IN (618, 220210) AND v72.valuenum > 20 THEN 1 ELSE 0 END), 0)) AS composite_instability_score,
        aib.icu_los_days,
        aib.hospital_expire_flag
    FROM
        all_icu_base aib
    LEFT JOIN -- Use LEFT JOIN to keep all ICU stays, even if they have no vitals in the first 72h
        vitals_72hr v72
        ON aib.stay_id = v72.stay_id
    GROUP BY
        aib.subject_id, aib.hadm_id, aib.stay_id, aib.icu_los_days, aib.hospital_expire_flag
),
-- Step 5: Filter for the specific cohort and calculate their instability scores, then determine quartiles
cohort_scores AS (
    SELECT
        isa.subject_id,
        isa.hadm_id,
        isa.stay_id,
        isa.hr_unstable_cnt,
        isa.map_unstable_cnt,
        isa.rr_unstable_cnt,
        isa.composite_instability_score,
        isa.icu_los_days,
        isa.hospital_expire_flag,
        -- NTILE(4) assigns quartile numbers; DESC ensures higher instability scores are in quartile 1
        NTILE(4) OVER (ORDER BY isa.composite_instability_score DESC) AS instability_quartile
    FROM
        instability_scores_all_icu isa
    INNER JOIN
        cohort_base cb
        ON isa.stay_id = cb.stay_id
),
-- Step 6: Calculate the 99th percentile of the composite instability score for the specific cohort
ninety_ninth_percentile AS (
    SELECT
        PERCENTILE_CONT(composite_instability_score, 0.99) OVER() AS p99_composite_score
    FROM
        cohort_scores
)
-- Step 7: Final comparison
SELECT
    'Most Unstable Quartile of Specific Cohort' AS group_name,
    AVG(cs.hr_unstable_cnt) AS avg_hr_unstable_count,
    AVG(cs.map_unstable_cnt) AS avg_map_unstable_count,
    AVG(cs.rr_unstable_cnt) AS avg_rr_unstable_count,
    AVG(cs.icu_los_days) AS avg_icu_los_days,
    AVG(CASE WHEN cs.hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) AS mortality_rate,
    (SELECT DISTINCT p99_composite_score FROM ninety_ninth_percentile) AS p99_instability_score_cohort
FROM
    cohort_scores cs
WHERE
    cs.instability_quartile = 1
GROUP BY 1 -- Grouping on 'group_name' to allow for aggregates and the scalar subquery
UNION ALL
SELECT
    'General ICU Population' AS group_name,
    AVG(isa.hr_unstable_cnt) AS avg_hr_unstable_count,
    AVG(isa.map_unstable_cnt) AS avg_map_unstable_count,
    AVG(isa.rr_unstable_cnt) AS avg_rr_unstable_count,
    AVG(isa.icu_los_days) AS avg_icu_los_days,
    AVG(CASE WHEN isa.hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) AS mortality_rate,
    NULL AS p99_instability_score_cohort -- Not applicable for general ICU population in this context
FROM
    instability_scores_all_icu isa
GROUP BY 1;