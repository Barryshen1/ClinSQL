WITH ich_cohort AS (
    SELECT
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        -- Calculate LOS in days using BigQuery's DATE_DIFF
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
        p.anchor_age
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 73 AND 83
        AND d.icd_code LIKE 'I61.%'
        AND d.icd_version = 10
),
instability_score AS (
    SELECT
        c.hadm_id,
        c.subject_id,
        -- Count distinct lab types with at least one abnormal value in 48 hours
        COUNT(DISTINCT CASE
            WHEN le.valuenum IS NOT NULL
                AND le.ref_range_lower IS NOT NULL
                AND le.ref_range_upper IS NOT NULL
                AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
            THEN le.itemid
            ELSE NULL
        END) AS instability_score
    FROM
        ich_cohort c
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON c.hadm_id = le.hadm_id
        AND le.charttime BETWEEN c.admittime AND DATE_ADD(c.admittime, INTERVAL 48 HOUR)
    GROUP BY
        c.hadm_id, c.subject_id
),
quartiles AS (
    SELECT
        *,
        NTILE(4) OVER (ORDER BY instability_score) AS quartile
    FROM
        instability_score
),
quartile_summary AS (
    SELECT
        quartile,
        COUNT(*) AS patient_count,
        ROUND(AVG(los), 2) AS mean_los,
        ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_rate
    FROM
        quartiles q
    INNER JOIN
        ich_cohort c
        ON q.hadm_id = c.hadm_id
    GROUP BY
        quartile
),
overall_mortality AS (
    SELECT
        ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS overall_mortality_rate
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions`
)
SELECT
    qs.quartile,
    qs.patient_count,
    qs.mean_los,
    qs.mortality_rate,
    om.overall_mortality_rate
FROM
    quartile_summary qs,
    overall_mortality om
ORDER BY
    qs.quartile;