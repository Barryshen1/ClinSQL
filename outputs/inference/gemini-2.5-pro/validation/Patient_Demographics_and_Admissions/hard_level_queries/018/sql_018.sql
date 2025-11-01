WITH all_admissions_ranked AS (
    -- For each patient, get all their admissions and the time of the next one
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.admission_location,
        a.insurance,
        p.gender,
        -- Calculate age at admission using the anchor year and admission time
        p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission,
        -- Get the start time of the next admission for this patient
        LEAD(a.admittime, 1) OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS next_admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON a.subject_id = p.subject_id
),
index_admissions AS (
    -- Identify the specific "index" admissions that match the cohort criteria
    SELECT
        ar.hadm_id,
        ar.admittime,
        ar.dischtime,
        ar.next_admittime
    FROM all_admissions_ranked AS ar
    -- Join with diagnoses to filter for the principal diagnosis
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON ar.hadm_id = dx.hadm_id
    WHERE
        -- Patient demographics
        ar.gender = 'F'
        AND ar.age_at_admission BETWEEN 58 AND 68
        -- Admission criteria
        AND ar.insurance = 'Medicare'
        AND ar.admission_location = 'EMERGENCY ROOM'
        -- Diagnosis criteria (principal diagnosis of femoral neck fracture)
        AND dx.seq_num = 1
        AND (
            (dx.icd_version = 9 AND dx.icd_code LIKE '820%')
            OR (dx.icd_version = 10 AND dx.icd_code LIKE 'S720%')
        )
    -- Ensure we only have one row per unique index admission
    GROUP BY
        ar.hadm_id,
        ar.admittime,
        ar.dischtime,
        ar.next_admittime
),
cohort_analysis AS (
    -- For the index admissions, calculate LOS and readmission status
    SELECT
        -- Calculate index length of stay in days
        DATETIME_DIFF(dischtime, admittime, DAY) AS index_los_days,

        -- Flag if readmitted within 30 days of discharge
        CASE
            WHEN DATETIME_DIFF(next_admittime, dischtime, DAY) <= 30 THEN 1
            ELSE 0
        END AS readmitted_30_days
    FROM index_admissions
    -- Ensure dischtime is not null to calculate LOS and readmission
    WHERE dischtime IS NOT NULL
)
SELECT
    -- Metric 1: 30-day readmission rate
    AVG(readmitted_30_days) * 100 AS readmission_rate_30_day_pct,

    -- Metric 2: Median index LOS for readmitted vs. non-readmitted
    APPROX_QUANTILES(
        CASE WHEN readmitted_30_days = 1 THEN index_los_days ELSE NULL END, 100
    )[OFFSET(50)] AS median_los_readmitted,

    APPROX_QUANTILES(
        CASE WHEN readmitted_30_days = 0 THEN index_los_days ELSE NULL END, 100
    )[OFFSET(50)] AS median_los_not_readmitted,

    -- Metric 3: Percent of initial stays > 8 days
    AVG(CASE WHEN index_los_days > 8 THEN 1.0 ELSE 0.0 END) * 100 AS pct_initial_stay_gt_8_days
FROM cohort_analysis;