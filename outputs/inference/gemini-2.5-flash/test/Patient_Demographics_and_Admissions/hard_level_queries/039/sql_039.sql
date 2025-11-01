WITH all_admissions_with_gaps AS (
    -- Step 2: Get all admissions for each patient with previous discharge and next admission times
    -- This is essential to correctly determine if a cohort admission is truly an 'index' admission
    -- (i.e., not a readmission from *any* prior admission) and if it leads to *any* subsequent readmission.
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        LAG(ad.dischtime) OVER (PARTITION BY ad.subject_id ORDER BY ad.admittime) AS prev_dischtime_any_admission,
        LEAD(ad.admittime) OVER (PARTITION BY ad.subject_id ORDER BY ad.admittime) AS next_admittime_any_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
),
cohort_base AS (
    -- Step 1: Define the core cohort of admissions based on specified criteria
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        DATE_DIFF(DATE(ad.dischtime), DATE(ad.admittime), DAY) AS los_days,
        (pa.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - pa.anchor_year)) AS age_at_admission,
        aag.prev_dischtime_any_admission,
        aag.next_admittime_any_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pa
        ON ad.subject_id = pa.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ad.subject_id = di.subject_id AND ad.hadm_id = di.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
        ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
    INNER JOIN
        all_admissions_with_gaps aag
        ON ad.subject_id = aag.subject_id AND ad.hadm_id = aag.hadm_id
    WHERE
        pa.gender = 'M'
        AND ad.insurance = 'Medicare'
        AND ad.admission_location = 'EMERGENCY ROOM'
        AND (pa.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - pa.anchor_year)) BETWEEN 65 AND 75
        AND di.seq_num = 1 -- Principal diagnosis
        AND di.icd_code IN ('51881', 'J9600', 'J9601', 'J9602', 'J9620', 'J9621', 'J9622') -- Acute respiratory failure
),
cohort_processed AS (
    -- Step 3: Classify each cohort admission as an 'index' admission and determine if it leads to a readmission
    SELECT
        *,
        -- An admission is an index admission if it's the first for the patient, or if more than 30 days passed since previous discharge (any type).
        (prev_dischtime_any_admission IS NULL OR DATE_DIFF(DATE(admittime), DATE(prev_dischtime_any_admission), DAY) > 30) AS is_index_cohort_admission,
        -- An index cohort admission leads to a 30-day readmission if a subsequent admission (any type) occurs within 30 days of its discharge.
        (next_admittime_any_admission IS NOT NULL AND DATE_DIFF(DATE(next_admittime_any_admission), DATE(dischtime), DAY) <= 30) AS leads_to_30day_readmission
    FROM
        cohort_base
),
summary_metrics AS (
    -- Step 4: Calculate aggregated metrics based on the classified cohort admissions
    SELECT
        -- Count only the index cohort admissions for the denominator of rates and median LOS calculations
        COUNT(CASE WHEN is_index_cohort_admission THEN hadm_id END) AS total_index_admissions,
        -- Count index admissions that led to a 30-day readmission for the rate numerator
        COUNT(CASE WHEN is_index_cohort_admission AND leads_to_30day_readmission THEN hadm_id END) AS index_admissions_leading_to_readmission,
        -- Median LOS for index admissions that led to readmission
        APPROX_QUANTILES(CASE WHEN is_index_cohort_admission AND leads_to_30day_readmission THEN los_days END, 100)[OFFSET(50)] AS median_los_of_readmitted_index,
        -- Median LOS for index admissions that did NOT lead to readmission
        APPROX_QUANTILES(CASE WHEN is_index_cohort_admission AND NOT leads_to_30day_readmission THEN los_days END, 100)[OFFSET(50)] AS median_los_of_non_readmitted_index,
        -- Count index admissions with LOS > 9 days for the percentage calculations
        COUNT(CASE WHEN is_index_cohort_admission AND los_days > 9 THEN hadm_id END) AS index_admissions_los_gt_9_days
    FROM
        cohort_processed
)
-- Step 5: Final selection of calculated metrics
SELECT
    -- Calculate 30-day readmission rate (as percentage)
    SAFE_DIVIDE(t.index_admissions_leading_to_readmission, t.total_index_admissions) * 100.0 AS readmission_rate_30_day,
    -- Median index LOS for readmitted patients
    t.median_los_of_readmitted_index,
    -- Median index LOS for non-readmitted patients
    t.median_los_of_non_readmitted_index,
    -- Calculate percent LOS > 9 days (as percentage)
    SAFE_DIVIDE(t.index_admissions_los_gt_9_days, t.total_index_admissions) * 100.0 AS percent_los_gt_9_days
FROM
    summary_metrics t;