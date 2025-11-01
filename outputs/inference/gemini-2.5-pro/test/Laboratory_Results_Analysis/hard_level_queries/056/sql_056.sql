WITH cohort AS (
    SELECT
        p.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
            ON p.subject_id = adm.subject_id
    WHERE
        p.gender = 'F'
        -- Calculate age at admission and filter for the 55-65 range.
        AND (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year + p.anchor_age) BETWEEN 55 AND 65
),

-- CTE 2: Calculate the lab instability score and total labs for each admission in the cohort.
lab_scores AS (
    SELECT
        c.hadm_id,
        c.admittime,
        c.dischtime,
        c.hospital_expire_flag,
        -- The score is the count of abnormal labs in the first 48 hours.
        COUNTIF(le.flag = 'abnormal') AS lab_instability_score,
        -- Total labs measured in the same period.
        COUNT(le.labevent_id) AS total_labs
    FROM
        cohort AS c
    LEFT JOIN -- LEFT JOIN is crucial to include patients with no labs (score = 0).
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON c.hadm_id = le.hadm_id
        -- Filter labs to the first 48 hours of admission.
        AND le.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
    GROUP BY
        c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag
),

-- CTE 3: Determine the 95th percentile threshold for the instability score.
score_threshold AS (
    SELECT
        -- APPROX_QUANTILES is an efficient way to find percentiles.
        APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(95)] AS p95_threshold
    FROM
        lab_scores
),

-- CTE 4: Assign patients to groups based on the threshold and calculate individual LOS.
patient_groups AS (
    SELECT
        ls.hadm_id,
        ls.hospital_expire_flag,
        DATETIME_DIFF(ls.dischtime, ls.admittime, DAY) AS los_days,
        ls.lab_instability_score, -- This is the sum of abnormal labs per patient.
        ls.total_labs, -- This is the sum of all labs per patient.
        CASE
            WHEN ls.lab_instability_score >= st.p95_threshold THEN 'Top Tier (>=95th percentile)'
            ELSE 'General Population (<95th percentile)'
        END AS patient_group
    FROM
        lab_scores AS ls,
        score_threshold AS st -- Cross join with the single-row threshold table.
)

-- Final step: Aggregate the metrics for each group and present the comparison.
SELECT
    pg.patient_group,
    COUNT(DISTINCT pg.hadm_id) AS number_of_patients,
    AVG(pg.los_days) AS avg_length_of_stay_days,
    AVG(pg.hospital_expire_flag) AS mortality_rate,
    -- Critical lab rate = (Total abnormal labs in group) / (Total labs in group).
    SAFE_DIVIDE(SUM(pg.lab_instability_score), SUM(pg.total_labs)) AS critical_lab_rate
FROM
    patient_groups AS pg
GROUP BY
    pg.patient_group
ORDER BY
    -- Show "Top Tier" first for easier comparison.
    pg.patient_group DESC;