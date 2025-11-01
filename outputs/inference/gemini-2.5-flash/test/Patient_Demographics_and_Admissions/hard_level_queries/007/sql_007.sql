WITH base_patients AS (
    SELECT
        p.subject_id,
        p.gender,
        p.anchor_age,
        p.anchor_year,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        a.admission_location,
        a.insurance,
        -- Calculate LOS in days, using hours for precision before dividing
        TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
        -- Calculate age at admission time
        (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON a.hadm_id = di.hadm_id AND a.subject_id = di.subject_id
    WHERE
        p.gender = 'M'
        AND a.admission_location = 'EMERGENCY ROOM'
        AND a.insurance = 'Medicare'
        AND di.seq_num = 1 -- Principal diagnosis
        AND (
               (di.icd_version = 9 AND di.icd_code LIKE '435%') -- ICD-9 codes for Transient Ischemic Attack (TIA)
            OR (di.icd_version = 10 AND di.icd_code LIKE 'G45%') -- ICD-10 codes for Transient Ischemic Attack (TIA)
        )
),
eligible_index_admissions AS (
    SELECT
        subject_id,
        hadm_id,
        admittime AS index_admittime,
        dischtime AS index_dischtime,
        los_days AS index_los_days,
        hospital_expire_flag
    FROM
        base_patients
    WHERE
        age_at_admission BETWEEN 83 AND 93
),
-- Step 2: Determine readmission status for all admissions for the identified subjects
-- This CTE gets the next admission time for *any* admission for a given subject
all_admissions_with_next_event AS (
    SELECT
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        hospital_expire_flag,
        -- Get the next admission time for this subject, ordered by admit time
        LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime_for_subject
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions`
),
-- Step 3: Join back to eligible index admissions to flag 30-day readmissions
index_admissions_with_readmission_status AS (
    SELECT
        eia.subject_id,
        eia.hadm_id,
        eia.index_admittime,
        eia.index_dischtime,
        eia.index_los_days,
        eia.hospital_expire_flag,
        ane.next_admittime_for_subject,
        -- Flag for 30-day readmission:
        -- Patient must not have died during the index admission
        -- There must be a subsequent admission
        -- The subsequent admission must be within 30 days of the index discharge
        CASE
            WHEN eia.hospital_expire_flag = 0  -- Patient was discharged alive from index admission
                 AND ane.next_admittime_for_subject IS NOT NULL -- There was a subsequent admission
                 AND TIMESTAMP_DIFF(ane.next_admittime_for_subject, eia.index_dischtime, DAY) <= 30
            THEN 1
            ELSE 0
        END AS has_30_day_readmission
    FROM
        eligible_index_admissions eia
    INNER JOIN -- Use INNER JOIN as we are specifically interested in the next event for our eligible index admissions
        all_admissions_with_next_event ane
        ON eia.subject_id = ane.subject_id AND eia.hadm_id = ane.hadm_id
)
-- Step 4: Calculate the requested metrics
SELECT
    COUNT(DISTINCT hadm_id) AS total_index_admissions,
    -- 30-day readmission rate
    ROUND(CAST(SUM(has_30_day_readmission) AS BIGNUMERIC) * 100 / COUNT(DISTINCT hadm_id), 2) AS readmission_rate_percent,
    -- Median Index LOS for readmitted patients
    APPROX_QUANTILES(CASE WHEN has_30_day_readmission = 1 THEN index_los_days END, 2)[OFFSET(1)] AS median_index_los_readmitted_days,
    -- Median Index LOS for non-readmitted patients
    APPROX_QUANTILES(CASE WHEN has_30_day_readmission = 0 THEN index_los_days END, 2)[OFFSET(1)] AS median_index_los_non_readmitted_days,
    -- Percent of index stays > 10 days
    ROUND(CAST(COUNTIF(index_los_days > 10) AS BIGNUMERIC) * 100 / COUNT(DISTINCT hadm_id), 2) AS percent_index_stays_gt_10_days
FROM
    index_admissions_with_readmission_status;