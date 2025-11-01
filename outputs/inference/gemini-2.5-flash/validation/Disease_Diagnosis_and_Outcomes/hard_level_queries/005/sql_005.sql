WITH cohort_admissions AS (
    -- Identify the target cohort: Female inpatients aged 43-53 with heart failure and an ICU stay
    SELECT DISTINCT
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        p.dod, -- Date of death from patients table
        i.stay_id,
        i.los AS icu_los, -- ICU Length of Stay
        -- Mock risk score: For demonstration, replace with actual derived risk score in a real analysis.
        -- Using MOD(hadm_id, 100) to get a value between 0 and 99, then scale it.
        CAST(MOD(a.hadm_id, 100) AS BIGNUMERIC) / 10.0 AS mock_risk_score,
        -- Mock major complication flag: For demonstration, replace with actual derived complication logic.
        -- Assigns '1' (complication) to ~20% of admissions based on hadm_id.
        CASE WHEN MOD(a.hadm_id, 5) = 0 THEN 1 ELSE 0 END AS mock_major_complication_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp`.patients p
        INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON p.subject_id = a.subject_id
        INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d_icd ON a.hadm_id = d_icd.hadm_id
        INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i ON a.hadm_id = i.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 43 AND 53
        -- Filter for Heart Failure diagnoses (ICD-9: 428%, ICD-10: I50%)
        AND (
            (d_icd.icd_version = 9 AND d_icd.icd_code LIKE '428%') OR
            (d_icd.icd_version = 10 AND d_icd.icd_code LIKE 'I50%')
        )
),
cohort_summary_metrics AS (
    -- Calculate aggregated metrics for the identified cohort
    SELECT
        -- Median (50th percentile) and IQR (25th, 75th percentiles) of the mock risk score
        APPROX_QUANTILES(mock_risk_score, 100)[OFFSET(50)] AS median_risk_score,
        APPROX_QUANTILES(mock_risk_score, 100)[OFFSET(25)] AS q1_risk_score,
        APPROX_QUANTILES(mock_risk_score, 100)[OFFSET(75)] AS q3_risk_score,
        -- 30-day mortality rate: 1.0 if patient died within 30 days of admittime, 0.0 otherwise
        AVG(CASE WHEN dod IS NOT NULL AND DATE_DIFF(dod, admittime, DAY) <= 30 THEN 1.0 ELSE 0.0 END) AS thirty_day_mortality_rate,
        -- Major complication rate: Average of the mock complication flag
        AVG(CAST(mock_major_complication_flag AS BIGNUMERIC)) AS major_complication_rate,
        -- Average ICU LOS among survivors (patients not deceased within 30 days of admission)
        AVG(CASE WHEN NOT (dod IS NOT NULL AND DATE_DIFF(dod, admittime, DAY) <= 30) THEN icu_los ELSE NULL END) AS avg_icu_los_survivors
    FROM
        cohort_admissions
),
all_females_43_53_scores AS (
    -- Generate mock risk scores for all females aged 43-53 (comparison group for percentile rank)
    SELECT DISTINCT
        a.hadm_id,
        CAST(MOD(a.hadm_id, 100) AS BIGNUMERIC) / 10.0 AS mock_risk_score
    FROM
        `physionet-data.mimiciv_3_1_hosp`.patients p
        INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON p.subject_id = a.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 43 AND 53
)
-- Final selection combining all calculated metrics
SELECT
    cs.median_risk_score,
    cs.q1_risk_score,
    cs.q3_risk_score,
    FORMAT("%.2f", cs.thirty_day_mortality_rate * 100) || '%' AS thirty_day_mortality_rate,
    FORMAT("%.2f", cs.major_complication_rate * 100) || '%' AS major_complication_rate,
    cs.avg_icu_los_survivors,
    (
        -- Calculate the percentile of the cohort's median risk score within the comparison population
        -- This counts how many scores in the broader group are less than or equal to the cohort's median
        COUNTIF(afs.mock_risk_score <= cs.median_risk_score) * 100.0 / COUNT(afs.mock_risk_score)
    ) AS risk_percentile_vs_all_females_43_53
FROM
    cohort_summary_metrics cs,
    all_females_43_53_scores afs -- Use afs for the COUNT and for comparison
GROUP BY
    cs.median_risk_score, cs.q1_risk_score, cs.q3_risk_score,
    cs.thirty_day_mortality_rate, cs.major_complication_rate, cs.avg_icu_los_survivors;