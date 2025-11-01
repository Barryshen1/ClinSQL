WITH Admissions_Base AS (
    -- Base CTE for all admissions, linking patient demographics and death information
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.deathtime,
        pat.gender,
        pat.anchor_age,
        pat.dod
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
            ON ad.subject_id = pat.subject_id
),
Admission_DiagCounts AS (
    -- Calculate the number of distinct diagnoses (our "risk score") per admission
    SELECT
        ab.subject_id,
        ab.hadm_id,
        ab.admittime,
        ab.dischtime,
        ab.deathtime,
        ab.gender,
        ab.anchor_age,
        ab.dod,
        COUNT(DISTINCT di.icd_code) AS num_diagnoses_per_admission
    FROM
        Admissions_Base AS ab
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
            ON ab.hadm_id = di.hadm_id
    GROUP BY
        ab.subject_id, ab.hadm_id, ab.admittime, ab.dischtime, ab.deathtime, ab.gender, ab.anchor_age, ab.dod
),
Septic_Shock_Admissions AS (
    -- Identify admissions with Septic Shock diagnoses (ICD-9 and ICD-10)
    SELECT DISTINCT
        hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 10 AND icd_code = 'R6521') -- ICD-10 for Septic shock
        OR (icd_version = 9 AND icd_code = '78552') -- ICD-9 for Septic shock
),
Major_Complication_Admissions AS (
    -- Identify admissions with example Major Complication diagnoses (ICD-9 and ICD-10)
    -- NOTE: These are illustrative ICD codes for major complications.
    -- A clinical expert should validate this list for research purposes.
    SELECT DISTINCT
        hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 10 AND icd_code IN ('T814XXA', 'T80211A', 'A419', 'N179', 'I2699', 'J95851', 'K6811')) -- e.g., Postprocedural infection, Central line-associated bloodstream infection, Sepsis, AKI, PE, Ventilator associated pneumonia, Postprocedural abscess.
        OR (icd_version = 9 AND icd_code IN ('99859', '99933', '78559', '5849', '41519', '99731', '56721')) -- e.g., Postop infection, Central line infection, Septic shock (unspec), AKI, PE, Ventilator associated pneumonia, Postprocedural abdominal abscess.
),
DiagCounts_For_Percentile_Population AS (
    -- Get diagnosis counts for the reference population (Male, 63-73 years old)
    SELECT
        adc.num_diagnoses_per_admission
    FROM
        Admission_DiagCounts AS adc
    WHERE
        adc.gender = 'M'
        AND adc.anchor_age BETWEEN 63 AND 73
)
-- 1. Query for the Specific Cohort (63-73Y Male, Septic Shock, >15 Diagnoses)
SELECT
    'Specific Cohort (63-73Y Male, Septic Shock, >15 Diagnoses)' AS cohort_name,
    COUNT(DISTINCT adc.hadm_id) AS total_admissions,
    AVG(adc.num_diagnoses_per_admission) AS mean_risk_score_num_diagnoses,
    CAST(SUM(CASE
            WHEN
                (adc.deathtime IS NOT NULL AND DATE_DIFF(adc.deathtime, adc.admittime, DAY) <= 90)
                OR
                (adc.deathtime IS NULL AND adc.dod IS NOT NULL AND DATE_DIFF(adc.dod, adc.admittime, DAY) <= 90)
            THEN 1
            ELSE 0
        END) AS FLOAT64) * 100.0 / COUNT(adc.hadm_id) AS ninety_day_mortality_rate_percent,
    CAST(SUM(CASE WHEN mca.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS FLOAT64) * 100.0 / COUNT(DISTINCT adc.hadm_id) AS major_complication_rate_percent,
    AVG(
        CASE
            WHEN
                -- Patient survived past 90 days or never died
                NOT (
                   (adc.deathtime IS NOT NULL AND DATE_DIFF(adc.deathtime, adc.admittime, DAY) <= 90)
                    OR
                    (adc.deathtime IS NULL AND adc.dod IS NOT NULL AND DATE_DIFF(adc.dod, adc.admittime, DAY) <= 90)
                )
            THEN DATE_DIFF(adc.dischtime, adc.admittime, DAY)
            ELSE NULL
        END
    ) AS mean_survivor_los_days,
    CAST(NULL AS FLOAT64) AS percentile_of_diagnoses_for_profile -- Placeholder for UNION ALL
FROM
    Admission_DiagCounts AS adc
INNER JOIN
    Septic_Shock_Admissions AS ssa
        ON adc.hadm_id = ssa.hadm_id
LEFT JOIN
    Major_Complication_Admissions AS mca
        ON adc.hadm_id = mca.hadm_id
WHERE
    adc.gender = 'M'
    AND adc.anchor_age BETWEEN 63 AND 73
    AND adc.num_diagnoses_per_admission > 15
GROUP BY cohort_name

UNION ALL

-- 2. Query for General Inpatients
SELECT
    'General Inpatients' AS cohort_name,
    COUNT(DISTINCT adc.hadm_id) AS total_admissions,
    AVG(adc.num_diagnoses_per_admission) AS mean_risk_score_num_diagnoses,
    CAST(SUM(CASE
            WHEN
                (adc.deathtime IS NOT NULL AND DATE_DIFF(adc.deathtime, adc.admittime, DAY) <= 90)
                OR
                (adc.deathtime IS NULL AND adc.dod IS NOT NULL AND DATE_DIFF(adc.dod, adc.admittime, DAY) <= 90)
            THEN 1
            ELSE 0
        END) AS FLOAT64) * 100.0 / COUNT(adc.hadm_id) AS ninety_day_mortality_rate_percent,
    CAST(SUM(CASE WHEN mca.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS FLOAT64) * 100.0 / COUNT(DISTINCT adc.hadm_id) AS major_complication_rate_percent,
    AVG(
        CASE
            WHEN
                NOT (
                   (adc.deathtime IS NOT NULL AND DATE_DIFF(adc.deathtime, adc.admittime, DAY) <= 90)
                    OR
                    (adc.deathtime IS NULL AND adc.dod IS NOT NULL AND DATE_DIFF(adc.dod, adc.admittime, DAY) <= 90)
                )
            THEN DATE_DIFF(adc.dischtime, adc.admittime, DAY)
            ELSE NULL
        END
    ) AS mean_survivor_los_days,
    CAST(NULL AS FLOAT64) AS percentile_of_diagnoses_for_profile -- Placeholder for UNION ALL
FROM
    Admission_DiagCounts AS adc
LEFT JOIN
    Major_Complication_Admissions AS mca
        ON adc.hadm_id = mca.hadm_id
GROUP BY cohort_name

UNION ALL

-- 3. Query for Percentile calculation for a "68M, 16 Diagnoses" profile
SELECT
    'Percentile for 68M, 16 Diagnoses (among 63-73Y M population)' AS cohort_name,
    CAST(NULL AS INT64) AS total_admissions,
    CAST(NULL AS FLOAT64) AS mean_risk_score_num_diagnoses,
    CAST(NULL AS FLOAT64) AS ninety_day_mortality_rate_percent,
    CAST(NULL AS FLOAT64) AS major_complication_rate_percent,
    CAST(NULL AS FLOAT64) AS mean_survivor_los_days,
    -- Calculate the percentile: percentage of admissions in the reference population
    -- that have a number of diagnoses less than or equal to 16.
    (COUNTIF(num_diagnoses_per_admission <= 16) * 100.0 / COUNT(*)) AS percentile_of_diagnoses_for_profile
FROM
    DiagCounts_For_Percentile_Population
GROUP BY cohort_name;