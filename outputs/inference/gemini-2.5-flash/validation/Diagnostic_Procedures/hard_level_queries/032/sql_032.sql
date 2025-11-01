WITH PatientDemographics AS (
    SELECT
        p.subject_id,
        p.gender,
        p.anchor_age,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 66 AND 76
),
FirstICUStay AS (
    SELECT
        pd.subject_id,
        pd.hadm_id,
        pd.admittime,
        pd.dischtime,
        pd.hospital_expire_flag,
        ic.stay_id,
        ic.intime
    FROM PatientDemographics pd
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic
        ON pd.hadm_id = ic.hadm_id AND pd.subject_id = ic.subject_id
    QUALIFY ROW_NUMBER() OVER (PARTITION BY pd.subject_id ORDER BY ic.intime) = 1
),
SepsisStatus AS (
    SELECT
        fis.*,
        -- COALESCE handles cases where a subject/hadm_id combination might not be in sepsis3
        -- It defaults to 0 (not sepsis) if no match is found
        COALESCE(s3.sepsis3, 0) AS is_sepsis
    FROM FirstICUStay fis
    LEFT JOIN `physionet-data.mimiciv_derived.sepsis3` s3
        ON fis.subject_id = s3.subject_id AND fis.hadm_id = s3.hadm_id
),
-- CTE to calculate distinct procedure counts for sepsis patients within the first 48 hours
SepsisProcedureCounts AS (
    SELECT
        ss.stay_id,
        COUNT(DISTINCT pic.icd_code) AS distinct_procedure_count
    FROM SepsisStatus ss
    JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pic
        ON ss.subject_id = pic.subject_id AND ss.hadm_id = pic.hadm_id
    WHERE
        ss.is_sepsis = 1
        -- Procedures within the first 48 hours of an ICU stay.
        -- Since procedures_icd.chartdate is a DATE, this covers the day of intime and the next day.
        AND pic.chartdate >= DATE(ss.intime)
        AND pic.chartdate < DATE_ADD(DATE(ss.intime), INTERVAL 2 DAY)
    GROUP BY ss.stay_id
)
-- Main query - Part 1: Calculate the 90th percentile of distinct procedures for the sepsis cohort
SELECT
    '90th Percentile of Distinct Procedures (Sepsis Cohort)' AS metric,
    -- Using BigQuery's APPROX_QUANTILES for a more robust and idiomatic percentile calculation
    APPROX_QUANTILES(distinct_procedure_count, 100)[OFFSET(90)] AS value
FROM SepsisProcedureCounts
-- APPROX_QUANTILES without GROUP BY naturally returns a single aggregated row.
UNION ALL
-- Main query - Part 2: Compare Average Hospital LOS (Days) between Sepsis and Control Cohorts
SELECT
    CASE
        WHEN s.is_sepsis = 1 THEN 'Average Hospital LOS (Days) - Sepsis Cohort'
        ELSE 'Average Hospital LOS (Days) - Control Cohort'
    END AS metric,
    AVG(DATETIME_DIFF(s.dischtime, s.admittime, HOUR) / 24.0) AS value
FROM SepsisStatus s
GROUP BY s.is_sepsis
UNION ALL
-- Main query - Part 3: Compare In-hospital Mortality Rate (%) between Sepsis and Control Cohorts
SELECT
    CASE
        WHEN s.is_sepsis = 1 THEN 'In-hospital Mortality Rate (%) - Sepsis Cohort'
        ELSE 'In-hospital Mortality Rate (%) - Control Cohort'
    END AS metric,
    SUM(s.hospital_expire_flag) * 100.0 / COUNT(s.subject_id) AS value
FROM SepsisStatus s
GROUP BY s.is_sepsis
ORDER BY metric;