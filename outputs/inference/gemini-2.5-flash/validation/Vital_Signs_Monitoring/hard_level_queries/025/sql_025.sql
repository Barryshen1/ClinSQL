WITH cohort_raw AS (
    -- Select foundational patient, admission, and ICU stay information
    SELECT
        p.subject_id,
        adm.hadm_id,
        icu.stay_id,
        p.gender,
        -- Calculate age at ICU admission
        p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) AS age_at_icu_admit,
        icu.intime,
        icu.outtime,
        -- Calculate ICU LOS in hours directly for consistency, as icu.los is in days
        DATETIME_DIFF(icu.outtime, icu.intime, HOUR) AS icu_los_hours,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.hadm_id = icu.hadm_id
),
cohort_patients AS (
    -- Filter for male patients, age 55-65 at ICU admit, with a diagnosis of cardiac arrest
    SELECT
        cr.*
    FROM
        cohort_raw cr
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON cr.subject_id = di.subject_id AND cr.hadm_id = di.hadm_id
    WHERE
        cr.gender = 'M'
        AND cr.age_at_icu_admit BETWEEN 55 AND 65
        AND (
            -- ICD-10 diagnosis codes for Cardiac arrest (e.g., I46.x)
            (di.icd_code LIKE 'I46%' AND di.icd_version = 10)
            -- ICD-9 diagnosis code for Cardiac arrest (427.5, stored as 4275)
            OR (di.icd_code = '4275' AND di.icd_version = 9)
        )
),
first_24h_vitals AS (
    -- Extract relevant vital sign measurements within the first 24 hours of ICU admission
    SELECT
        cp.subject_id,
        cp.hadm_id,
        cp.stay_id,
        ce.itemid,
        ce.valuenum
    FROM
        cohort_patients cp
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON cp.subject_id = ce.subject_id AND cp.hadm_id = ce.hadm_id AND cp.stay_id = ce.stay_id
    WHERE
        ce.charttime BETWEEN cp.intime AND DATETIME_ADD(cp.intime, INTERVAL 24 HOUR)
        AND ce.valuenum IS NOT NULL -- Only consider numeric values
        AND ce.itemid IN (
            220045, -- Heart Rate
            220210, -- Respiratory Rate
            220179, 220050, -- SBP (Non-invasive Blood Pressure systolic, Arterial Blood Pressure systolic)
            220180, 220051, -- DBP (Non-invasive Blood Pressure diastolic, Arterial Blood Pressure diastolic)
            220181, 220052, -- MAP (Non-invasive Blood Pressure mean, Arterial Blood Pressure mean)
            223761, -- Temperature Fahrenheit
            220277  -- SpO2 (O2 saturation pulseoxymetry)
        )
),
vital_instability_points AS (
    -- Assign 1 point for each vital sign measurement that falls outside its normal range
    SELECT
        f2h.subject_id,
        f2h.hadm_id,
        f2h.stay_id,
        CASE
            -- Heart Rate: <50 or >100 bpm
            WHEN f2h.itemid = 220045 AND (f2h.valuenum < 50 OR f2h.valuenum > 100) THEN 1
            -- Respiratory Rate: <12 or >20 bpm
            WHEN f2h.itemid = 220210 AND (f2h.valuenum < 12 OR f2h.valuenum > 20) THEN 1
            -- SBP: <90 or >160 mmHg
            WHEN f2h.itemid IN (220179, 220050) AND (f2h.valuenum < 90 OR f2h.valuenum > 160) THEN 1
            -- DBP: <50 or >100 mmHg
            WHEN f2h.itemid IN (220180, 220051) AND (f2h.valuenum < 50 OR f2h.valuenum > 100) THEN 1
            -- MAP: <65 or >100 mmHg
            WHEN f2h.itemid IN (220181, 220052) AND (f2h.valuenum < 65 OR f2h.valuenum > 100) THEN 1
            -- Temperature F: <96.8 F or >100.4 F (approx 36-38 C)
            WHEN f2h.itemid = 223761 AND (f2h.valuenum < 96.8 OR f2h.valuenum > 100.4) THEN 1
            -- SpO2: <90%
            WHEN f2h.itemid = 220277 AND f2h.valuenum < 90 THEN 1
            ELSE 0
        END AS instability_point
    FROM
        first_24h_vitals f2h
),
patient_instability_scores AS (
    -- Aggregate total instability score per patient ICU stay
    SELECT
        cp.subject_id,
        cp.hadm_id,
        cp.stay_id,
        COALESCE(SUM(vip.instability_point), 0) AS vital_instability_score, -- Use COALESCE to assign 0 if no abnormal points
        cp.icu_los_hours,
        cp.hospital_expire_flag
    FROM
        cohort_patients cp
    LEFT JOIN -- Use LEFT JOIN to include patients who might have no recorded abnormal vitals (score 0)
        vital_instability_points vip
        ON cp.subject_id = vip.subject_id AND cp.hadm_id = vip.hadm_id AND cp.stay_id = vip.stay_id
    GROUP BY
        cp.subject_id, cp.hadm_id, cp.stay_id, cp.icu_los_hours, cp.hospital_expire_flag
),
final_scores_with_rank AS (
    SELECT
        pis.*,
        -- Assign decile rank based on instability score (1 = most unstable, i.e., highest score)
        NTILE(10) OVER (ORDER BY vital_instability_score DESC) AS unstable_decile_rank
    FROM
        patient_instability_scores pis
)
-- Final calculation of requested metrics
SELECT
    -- 1. What percentile is a first-24h vital-sign instability score of 70?
    -- This is calculated as the percentage of patients with a score <= 70.
    CAST(SUM(CASE WHEN final_scores_with_rank.vital_instability_score <= 70 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS BIGNUMERIC) AS percentile_of_score_70,

    -- 2. Mean ICU LOS for the most unstable decile (top 10% by instability score)
    -- icu_los_hours is now correctly in hours, so dividing by 24.0 converts to days.
    AVG(CASE WHEN final_scores_with_rank.unstable_decile_rank = 1 THEN final_scores_with_rank.icu_los_hours / 24.0 END) AS mean_icu_los_unstable_decile_days,

    -- 3. Mortality for the most unstable decile (percentage of hospital deaths)
    AVG(CASE WHEN final_scores_with_rank.unstable_decile_rank = 1 THEN final_scores_with_rank.hospital_expire_flag END) * 100 AS mortality_unstable_decile_percent
FROM
    final_scores_with_rank;