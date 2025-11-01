WITH
-- Step 1: Filter admissions for males and calculate age at admission
hadm_age_gender_filtered AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        p.dod,
        a.dischtime,
        a.hospital_expire_flag,
        -- Standard age calculation for MIMIC-IV
        (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age AS age
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
),

-- Step 2: Identify admissions with a diagnosis of septic shock
septic_shock_dx AS (
    SELECT DISTINCT dx.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
      ON dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
    WHERE
        -- Find septic shock by text search or specific codes for robustness
        d.long_title LIKE '%Septic shock%' OR dx.icd_code IN ('785.52', 'R65.21')
),

-- Step 3: Count the number of diagnoses for each admission
diag_counts AS (
    SELECT hadm_id, COUNT(DISTINCT icd_code) AS num_diagnoses
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY hadm_id
),

-- Step 4: Define the final septic shock cohort by combining the above criteria
septic_shock_cohort AS (
    SELECT
        f.hadm_id,
        f.subject_id,
        f.admittime,
        dc.num_diagnoses
    FROM hadm_age_gender_filtered AS f
    -- Join to bring in septic shock and diagnosis count information
    JOIN septic_shock_dx AS ss ON f.hadm_id = ss.hadm_id
    JOIN diag_counts AS dc ON f.hadm_id = dc.hadm_id
    -- Apply all filters for the cohort definition
    WHERE
        f.age BETWEEN 63 AND 73
        AND dc.num_diagnoses > 15
),

-- Step 5: Calculate the "Risk Score" = first lactate in first 24h for the cohort
first_lactate AS (
    SELECT
        le.hadm_id,
        le.valuenum AS first_lactate_val
    FROM (
        SELECT
            le.hadm_id,
            le.valuenum,
            ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) as rn
        FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
        JOIN septic_shock_cohort ssc ON le.hadm_id = ssc.hadm_id
        JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli ON le.itemid = dli.itemid
        WHERE dli.label = 'Lactate'
          AND le.valuenum IS NOT NULL
          AND le.charttime <= DATETIME_ADD(ssc.admittime, INTERVAL 24 HOUR)
    ) le
    WHERE le.rn = 1
),

-- Step 6: Calculate mortality, LOS, and complications for ALL admissions
all_admission_metrics AS (
    SELECT
        a.hadm_id,
        a.hospital_expire_flag,
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        -- 90-day mortality flag
        CASE
            WHEN a.dod IS NOT NULL AND DATE_DIFF(DATE(a.dod), DATE(a.admittime), DAY) BETWEEN 0 AND 90 THEN 1
            ELSE 0
        END AS mortality_90_day,
        -- Major complication flag (using a subquery for clarity)
        CASE
            WHEN a.hadm_id IN (
                SELECT DISTINCT hadm_id
                FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
                WHERE seq_num > 1 AND ( -- Heuristic: Complications are not the primary diagnosis
                    (icd_version = 9 AND (icd_code LIKE '584%' OR icd_code LIKE '51881%' OR icd_code LIKE '4275%')) OR
                    (icd_version = 10 AND (icd_code LIKE 'N17%' OR icd_code LIKE 'J960%' OR icd_code LIKE 'J962%' OR icd_code LIKE 'I46%'))
                )
            ) THEN 1
            ELSE 0
        END AS has_major_complication
    FROM hadm_age_gender_filtered a
),

-- Step 7: Combine all admissions with their metrics and cohort flag
final_data AS (
    SELECT
        a.hadm_id,
        CASE WHEN ssc.hadm_id IS NOT NULL THEN 'Septic Shock Cohort' ELSE 'General Inpatients' END AS patient_group,
        am.mortality_90_day,
        am.los_days,
        am.hospital_expire_flag,
        am.has_major_complication,
        fl.first_lactate_val
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    LEFT JOIN septic_shock_cohort ssc ON a.hadm_id = ssc.hadm_id
    LEFT JOIN all_admission_metrics am ON a.hadm_id = am.hadm_id
    LEFT JOIN first_lactate fl ON a.hadm_id = fl.hadm_id
)

-- Step 8: Final aggregation to produce the comparison table
SELECT
    patient_group,
    COUNT(hadm_id) AS number_of_admissions,
    -- Mean risk score (first lactate), only calculated for the septic shock cohort
    AVG(first_lactate_val) AS mean_risk_score_first_lactate,
    -- 90-day mortality for both groups
    AVG(mortality_90_day) AS mean_90_day_mortality_rate,
    -- Major complication rate for both groups
    AVG(has_major_complication) AS major_complication_rate,
    -- Survivor LOS for both groups
    AVG(CASE WHEN hospital_expire_flag = 0 THEN los_days ELSE NULL END) AS mean_survivor_los_days,
    -- Percentile for a patient with 16 diagnoses, calculated only for the septic shock cohort row
    CASE
        WHEN patient_group = 'Septic Shock Cohort' THEN (
             -- This subquery calculates the proportion of the cohort with <= 16 diagnoses.
             -- Since the cohort is defined as >15 diagnoses, this is effectively the percentile rank for 16.
             SELECT
                SAFE_DIVIDE(
                    COUNTIF(num_diagnoses <= 16),
                    COUNT(hadm_id)
                )
             FROM septic_shock_cohort
        )
        ELSE NULL
    END AS percentile_for_16_diagnoses_in_cohort
FROM final_data
WHERE patient_group IS NOT NULL AND hadm_id IS NOT NULL AND mortality_90_day IS NOT NULL
GROUP BY patient_group
ORDER BY patient_group DESC;