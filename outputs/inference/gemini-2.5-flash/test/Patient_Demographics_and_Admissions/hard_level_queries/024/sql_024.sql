WITH final_cohort AS (
    -- Step 1: Identify all admissions for patients meeting basic demographic and admission criteria
    WITH initial_cohort AS (
        SELECT
            adm.subject_id,
            adm.hadm_id,
            adm.admittime,
            adm.dischtime,
            pat.anchor_age,
            adm.hospital_expire_flag -- Get hospital_expire_flag for the index admission
        FROM
            `physionet-data.mimiciv_3_1_hosp.admissions` adm
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.patients` pat
            ON adm.subject_id = pat.subject_id
        WHERE
            pat.gender = 'M'
            AND pat.anchor_age BETWEEN 76 AND 86
            AND adm.insurance = 'Medicare'
            AND adm.admission_location = 'EMERGENCY ROOM'
    ),
    -- Step 2: Filter for admissions with principal diagnosis of ischemic stroke
    ischemic_stroke_admissions AS (
        SELECT
            ic.subject_id,
            ic.hadm_id,
            ic.admittime,
            ic.dischtime,
            ic.hospital_expire_flag
        FROM
            initial_cohort ic
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            ON ic.subject_id = di.subject_id AND ic.hadm_id = di.hadm_id
        WHERE
            di.seq_num = 1 -- Principal diagnosis
            AND (
                (di.icd_version = 9 AND di.icd_code LIKE '434%') -- ICD-9 for ischemic stroke (Cerebral embolism, thrombosis, and unspecified occlusion of cerebral arteries)
                OR
                (di.icd_version = 10 AND di.icd_code LIKE 'I63%') -- ICD-10 for ischemic stroke (Cerebral infarction)
            )
    ),
    -- Step 3: Determine the index admission for each patient (first qualifying admission)
    index_admissions AS (
        SELECT
            subject_id,
            hadm_id,
            admittime,
            dischtime,
            hospital_expire_flag,
            -- Calculate LOS in days. DATE_DIFF returns an integer.
            DATE_DIFF(dischtime, admittime, DAY) AS index_los_days
        FROM (
            SELECT
                subject_id,
                hadm_id,
                admittime,
                dischtime,
                hospital_expire_flag,
                ROW_NUMBER() OVER(PARTITION BY subject_id ORDER BY admittime ASC, hadm_id ASC) as rn -- Added hadm_id for consistent tie-breaking
            FROM
                ischemic_stroke_admissions
        ) AS ranked_ischemic_strokes
        WHERE rn = 1
    ),
    -- Step 4: Identify all subsequent admissions for these subjects
    all_possible_readmissions AS (
        SELECT
            ia.subject_id,
            ia.hadm_id AS index_hadm_id,
            ia.dischtime AS index_dischtime,
            adm_sub.hadm_id AS subsequent_hadm_id,
            adm_sub.admittime AS subsequent_admittime
        FROM
            index_admissions ia
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.admissions` adm_sub
            ON ia.subject_id = adm_sub.subject_id
        WHERE
            TRUE
            AND adm_sub.admittime > ia.dischtime -- Subsequent admission must start after index discharge
            AND adm_sub.hadm_id != ia.hadm_id -- Must be a different hospital admission
            -- For all-cause readmission, we count any subsequent admission, regardless of its outcome or type.
            -- Therefore, no filter for adm_sub.hospital_expire_flag here.
    )
    -- Step 5: Determine if an index admission resulted in a 30-day readmission
    -- This CTE (`final_cohort`) will list each index admission along with a flag for 30-day readmission
    SELECT
        ia.subject_id,
        ia.hadm_id AS index_hadm_id,
        ia.admittime AS index_admittime,
        ia.dischtime AS index_dischtime,
        ia.index_los_days,
        ia.hospital_expire_flag AS index_hosp_expire_flag, -- Use the flag from the index admission
        -- Check for readmission within 30 days. If multiple readmissions exist, any one counts.
        COALESCE(MAX(CASE WHEN pa.subsequent_hadm_id IS NOT NULL AND DATE_DIFF(pa.subsequent_admittime, ia.dischtime, DAY) <= 30 THEN TRUE ELSE FALSE END), FALSE) AS readmitted_30_days
    FROM
        index_admissions ia
    LEFT JOIN
        all_possible_readmissions pa
        ON ia.subject_id = pa.subject_id AND ia.hadm_id = pa.index_hadm_id
    GROUP BY
        ia.subject_id, ia.hadm_id, ia.admittime, ia.dischtime, ia.index_los_days, ia.hospital_expire_flag
)
SELECT
    -- 30-day all-cause readmission rate
    -- Denominator for readmission rate should only include patients discharged alive from the index stay,
    -- as patients who died during the index admission cannot be readmitted.
    SAFE_DIVIDE(
        COUNT(CASE WHEN fc.readmitted_30_days THEN 1 END),
        COUNT(CASE WHEN fc.index_hosp_expire_flag = 0 THEN 1 END) -- Denominator is count of eligible index admissions (discharged alive)
    ) * 100 AS readmission_rate_30_days,

    -- Median index LOS for readmitted patients
    -- Fix: Use CASE WHEN to conditionally include values for PERCENTILE_CONT, and remove redundant OVER ()
    PERCENTILE_CONT(
        CASE WHEN fc.readmitted_30_days THEN fc.index_los_days ELSE NULL END,
        0.5
    ) AS median_los_readmitted,

    -- Median index LOS for non-readmitted patients
    -- Only consider non-readmitted patients who were discharged alive from the index admission.
    -- Fix: Use CASE WHEN to conditionally include values for PERCENTILE_CONT, and remove redundant OVER ()
    PERCENTILE_CONT(
        CASE WHEN NOT fc.readmitted_30_days AND fc.index_hosp_expire_flag = 0 THEN fc.index_los_days ELSE NULL END,
        0.5
    ) AS median_los_non_readmitted,

    -- Percent index stays > 5 days (of all index stays that meet initial criteria, regardless of readmission or index outcome)
    SAFE_DIVIDE(
        COUNT(CASE WHEN fc.index_los_days > 5 THEN 1 END),
        COUNT(fc.index_hadm_id)
    ) * 100 AS percent_index_stays_gt_5_days
FROM
    final_cohort fc;