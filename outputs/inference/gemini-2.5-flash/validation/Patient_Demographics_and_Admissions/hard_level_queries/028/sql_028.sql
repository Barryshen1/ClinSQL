WITH initial_cohort_hadms AS (
    -- Step 1: Identify "index" admissions that meet all demographic and diagnosis criteria
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days -- Calculate LOS for the index stay here
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON adm.hadm_id = di.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 55 AND 65 -- Age 55-65 at first hospital admission
        AND adm.admission_location = 'EMERGENCY ROOM'
        AND adm.insurance = 'Medicare'
        AND di.seq_num = 1 -- Principal diagnosis (lowest seq_num indicates principal)
        -- Filter for cellulitis or erysipelas (superficial cellulitis)
        AND (LOWER(dd.long_title) LIKE '%cellulitis%' OR LOWER(dd.long_title) LIKE '%erysipelas%')
        AND adm.admittime IS NOT NULL AND adm.dischtime IS NOT NULL -- Ensure valid admission/discharge times for LOS calculation
),
all_subject_admissions AS (
    -- Step 2: Get all admissions for the subjects identified in the initial cohort
    -- This is necessary to correctly determine subsequent admissions for readmission calculations,
    -- even if those subsequent admissions don't meet the initial cohort criteria.
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    WHERE
        adm.subject_id IN (SELECT DISTINCT subject_id FROM initial_cohort_hadms)
        AND adm.admittime IS NOT NULL AND adm.dischtime IS NOT NULL -- Exclude invalid admission records from consideration for next admission
),
admissions_with_next_event AS (
    -- Step 3: For each admission of the identified subjects, find the next admission's admittime
    -- This uses a window function to look forward in time for each subject.
    SELECT
        asa.subject_id,
        asa.hadm_id,
        asa.admittime,
        asa.dischtime,
        asa.hospital_expire_flag,
        -- Find the admittance time of the next admission for the same patient
        LEAD(asa.admittime) OVER (PARTITION BY asa.subject_id ORDER BY asa.admittime) AS next_admittime_for_subject
    FROM
        all_subject_admissions asa
),
final_cohort_with_readmission_status AS (
    -- Step 4: Combine initial cohort with next event info to determine readmission status for the index stays
    SELECT
        ich.subject_id,
        ich.hadm_id,
        ich.los_days, -- LOS for the specific index stay (from the initial_cohort_hadms)
        ich.hospital_expire_flag, -- We need this from the index stay to filter for survivors
        CASE
            -- An index stay results in a 30-day readmission if:
            -- 1. The patient was discharged alive from the index stay (hospital_expire_flag = 0).
            -- 2. There was a subsequent admission for the same patient.
            -- 3. That subsequent admission occurred within 30 days of the index stay's discharge.
            WHEN ich.hospital_expire_flag = 0
                 AND awe.next_admittime_for_subject IS NOT NULL
                 AND DATETIME_DIFF(awe.next_admittime_for_subject, ich.dischtime, DAY) <= 30
            THEN 1 -- Marked as readmitted within 30 days
            -- An index stay results in no 30-day readmission if:
            -- 1. The patient was discharged alive from the index stay.
            -- 2. There was NO subsequent admission within 30 days (either no subsequent admit at all, or it was > 30 days).
            WHEN ich.hospital_expire_flag = 0
                 AND (awe.next_admittime_for_subject IS NULL OR DATETIME_DIFF(awe.next_admittime_for_subject, ich.dischtime, DAY) > 30)
            THEN 0 -- Marked as not readmitted within 30 days
            ELSE NULL -- Exclude this index stay from readmission calculations if patient expired during the stay (hospital_expire_flag = 1)
        END AS readmitted_30d_flag
    FROM
        initial_cohort_hadms ich
    INNER JOIN
        admissions_with_next_event awe
        ON ich.subject_id = awe.subject_id AND ich.hadm_id = awe.hadm_id
)
-- Step 5: Calculate the final aggregate metrics
SELECT
    COUNT(DISTINCT subject_id) AS total_patients_in_cohort,
    COUNT(hadm_id) AS total_index_admissions_in_cohort,

    -- 30-day readmission rate (as a proportion)
    -- Denominator includes only those index stays where readmission was possible (patient discharged alive)
    SAFE_DIVIDE(
        COUNT(CASE WHEN readmitted_30d_flag = 1 THEN 1 END), -- count readmitted
        COUNT(readmitted_30d_flag) -- count eligible for readmission (readmitted = 1 or not_readmitted = 0)
    ) AS thirty_day_readmission_rate,

    -- Median index LOS for readmitted patients (LOS in days)
    PERCENTILE_CONT(CASE WHEN fc.readmitted_30d_flag = 1 THEN fc.los_days END, 0.5) OVER() AS median_los_readmitted_days,
    -- Median index LOS for non-readmitted patients (LOS in days)
    PERCENTILE_CONT(CASE WHEN fc.readmitted_30d_flag = 0 THEN fc.los_days END, 0.5) OVER() AS median_los_non_readmitted_days,

    -- Percent of index stays > 7 days (as a proportion)
    SAFE_DIVIDE(
        COUNT(CASE WHEN fc.los_days > 7 THEN 1 END), -- count stays > 7 days
        COUNT(fc.los_days) -- count all index stays (where LOS is defined)
    ) AS percent_stays_gt_7_days
FROM
    final_cohort_with_readmission_status fc;