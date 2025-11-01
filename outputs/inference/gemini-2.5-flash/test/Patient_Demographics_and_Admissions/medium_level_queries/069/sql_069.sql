WITH cohort_admissions AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag,
        DATE_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days,
        CASE
            WHEN ad.hospital_expire_flag = 1 THEN 'Expired in-hospital'
            ELSE 'Discharged alive'
        END AS discharge_status
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 59 AND 69
        AND ad.admission_type = 'EMERGENCY'
        AND DATE_DIFF(ad.dischtime, ad.admittime, DAY) IS NOT NULL -- Exclude admissions with indeterminate LOS
        AND DATE_DIFF(ad.dischtime, ad.admittime, DAY) >= 0 -- Exclude illogical negative LOS
),
cohort_los_summary_by_status AS (
    SELECT
        discharge_status,
        COUNT(hadm_id) AS total_admissions,
        COUNT(CASE WHEN los_days >= 7 THEN 1 END) AS admissions_los_ge_7_days
    FROM
        cohort_admissions
    GROUP BY
        discharge_status
),
overall_cohort_los_metrics AS (
    SELECT
        COUNT(hadm_id) AS total_cohort_admissions,
        COUNT(CASE WHEN los_days <= 7 THEN 1 END) AS admissions_los_le_7_days
    FROM
        cohort_admissions
)
SELECT
    cls.discharge_status,
    cls.total_admissions,
    cls.admissions_los_ge_7_days,
    ROUND( (cls.admissions_los_ge_7_days * 100.0 / cls.total_admissions), 2) AS proportion_los_ge_7_percent,
    -- Fix: The alias 'oclm' was not defined within the subquery's FROM clause.
    -- Since overall_cohort_los_metrics is a single-row CTE, its columns can be directly referenced.
    (SELECT ROUND( (admissions_los_le_7_days * 100.0 / total_cohort_admissions), 2) FROM overall_cohort_los_metrics) AS percentile_rank_of_7_day_los_percent
FROM
    cohort_los_summary_by_status cls
ORDER BY
    cls.discharge_status;