WITH cohort_hhs AS (
    -- 1. Identify cohort: Male, 78-88 years old, with HHS diagnosis, and an ICU stay
    SELECT DISTINCT
        p.subject_id,
        adm.hadm_id,
        icu.stay_id,
        icu.intime AS icu_intime,
        adm.hospital_expire_flag AS in_hospital_mortality,
        icu.los AS icu_los
    FROM `physionet-data.mimiciv_3_1_hosp`.patients p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions adm
        ON p.subject_id = adm.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu
        ON adm.hadm_id = icu.hadm_id AND p.subject_id = icu.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 78 AND 88
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd dicd
            WHERE
                dicd.subject_id = adm.subject_id
                AND dicd.hadm_id = adm.hadm_id
                AND dicd.icd_code = 'E1165' -- ICD-10 for Type 2 diabetes mellitus with hyperglycemia, hyperosmolar coma (HHS)
                AND dicd.icd_version = 10
        )
),
first_24hr_vitals AS (
    -- 2. Extract vital signs for the first 24 hours of each ICU stay for the cohort
    SELECT
        ch.stay_id,
        ch.itemid,
        ch.valuenum
    FROM `physionet-data.mimiciv_3_1_icu`.chartevents ch
    INNER JOIN cohort_hhs co
        ON ch.stay_id = co.stay_id
    WHERE
        ch.charttime >= co.icu_intime
        AND ch.charttime <= DATETIME_ADD(co.icu_intime, INTERVAL 24 HOUR)
        AND ch.itemid IN (
            220045, -- Heart Rate
            220052, -- Arterial Blood Pressure Mean (MAP)
            220210  -- Respiratory Rate
        )
        AND ch.valuenum IS NOT NULL
        -- Apply reasonable physiological ranges to filter out obvious data entry errors
        AND (
            (ch.itemid = 220045 AND ch.valuenum BETWEEN 1 AND 300)   -- HR range
            OR (ch.itemid = 220052 AND ch.valuenum BETWEEN 1 AND 250)   -- MAP range
            OR (ch.itemid = 220210 AND ch.valuenum BETWEEN 1 AND 100)   -- RR range
        )
),
vital_stats AS (
    -- 3. Calculate mean and standard deviation for each vital sign per stay
    SELECT
        f24.stay_id,
        -- Heart Rate statistics
        AVG(CASE WHEN f24.itemid = 220045 THEN f24.valuenum END) AS hr_mean,
        STDDEV(CASE WHEN f24.itemid = 220045 THEN f24.valuenum END) AS hr_stddev,
        -- MAP statistics
        AVG(CASE WHEN f24.itemid = 220052 THEN f24.valuenum END) AS map_mean,
        STDDEV(CASE WHEN f24.itemid = 220052 THEN f24.valuenum END) AS map_stddev,
        -- Respiratory Rate statistics
        AVG(CASE WHEN f24.itemid = 220210 THEN f24.valuenum END) AS rr_mean,
        STDDEV(CASE WHEN f24.itemid = 220210 THEN f24.valuenum END) AS rr_stddev
    FROM first_24hr_vitals f24
    GROUP BY f24.stay_id
),
cv_calculation AS (
    -- 4. Calculate Coefficient of Variation (CV) for each vital sign
    SELECT
        vs.stay_id,
        -- HR CV: (STDDEV / MEAN) * 100. Handle cases where mean is zero or no data (STDDEV/MEAN could be NULL)
        CASE
            WHEN vs.hr_mean IS NULL OR vs.hr_mean = 0 OR vs.hr_stddev IS NULL THEN 0
            ELSE (vs.hr_stddev / vs.hr_mean) * 100
        END AS hr_cv,
        -- MAP CV
        CASE
            WHEN vs.map_mean IS NULL OR vs.map_mean = 0 OR vs.map_stddev IS NULL THEN 0
            ELSE (vs.map_stddev / vs.map_mean) * 100
        END AS map_cv,
        -- RR CV
        CASE
            WHEN vs.rr_mean IS NULL OR vs.rr_mean = 0 OR vs.rr_stddev IS NULL THEN 0
            ELSE (vs.rr_stddev / vs.rr_mean) * 100
        END AS rr_cv
    FROM vital_stats vs
),
abnormal_vital_flags AS (
    -- 5. Determine if any measurement for each vital sign was abnormal within 24 hours
    -- Normal ranges: HR (60-100), MAP (70-105), RR (12-20)
    SELECT
        co.stay_id,
        MAX(CASE WHEN f24.itemid = 220045 AND (f24.valuenum < 60 OR f24.valuenum > 100) THEN 1 ELSE 0 END) AS hr_abnormal_flag,
        MAX(CASE WHEN f24.itemid = 220052 AND (f24.valuenum < 70 OR f24.valuenum > 105) THEN 1 ELSE 0 END) AS map_abnormal_flag,
        MAX(CASE WHEN f24.itemid = 220210 AND (f24.valuenum < 12 OR f24.valuenum > 20) THEN 1 ELSE 0 END) AS rr_abnormal_flag
    FROM cohort_hhs co
    LEFT JOIN first_24hr_vitals f24
        ON co.stay_id = f24.stay_id
    GROUP BY co.stay_id
),
final_data_prep AS (
    -- 6. Combine all calculated metrics
    SELECT
        coh.subject_id,
        coh.hadm_id,
        coh.stay_id,
        coh.icu_los,
        coh.in_hospital_mortality,
        -- Stay Instability Score: Sum of CVs (treat missing CVs as 0)
        COALESCE(cvs.hr_cv, 0) + COALESCE(cvs.map_cv, 0) + COALESCE(cvs.rr_cv, 0) AS stay_instability_score,
        -- Abnormal Vital Count: Sum of flags (treat missing flags as 0)
        COALESCE(avf.hr_abnormal_flag, 0) + COALESCE(avf.map_abnormal_flag, 0) + COALESCE(avf.rr_abnormal_flag, 0) AS abnormal_vital_count
    FROM cohort_hhs coh
    LEFT JOIN cv_calculation cvs
        ON coh.stay_id = cvs.stay_id
    LEFT JOIN abnormal_vital_flags avf
        ON coh.stay_id = avf.stay_id
)
-- 7. Select top quartile by instability score and calculate decile
SELECT
    fdp.subject_id,
    fdp.hadm_id,
    fdp.stay_id,
    fdp.stay_instability_score,
    NTILE(10) OVER (ORDER BY fdp.stay_instability_score DESC) AS decile, -- Decile 1 is the highest 10%
    fdp.abnormal_vital_count,
    fdp.icu_los,
    fdp.in_hospital_mortality
FROM final_data_prep fdp
WHERE fdp.stay_instability_score IS NOT NULL -- Ensures only stays with some vital sign data contributing to CV are considered
QUALIFY NTILE(4) OVER (ORDER BY fdp.stay_instability_score DESC) = 1 -- Filter for the top quartile (highest 25%)
ORDER BY fdp.stay_instability_score DESC;