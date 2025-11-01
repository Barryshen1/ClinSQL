WITH cohort AS (
    -- Female patients aged 71-81 with complications of care (ICD-10 T80-T88)
    SELECT DISTINCT adm.subject_id, adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    WHERE pat.gender = 'F'
        AND pat.anchor_age BETWEEN 71 AND 81
        AND diag.icd_version = 10
        AND diag.icd_code BETWEEN 'T80' AND 'T88'
),

icu_status AS (
    -- Determine if each admission had an ICU stay
    SELECT adm.hadm_id,
           CASE WHEN MAX(icu.stay_id) IS NOT NULL THEN 1 ELSE 0 END AS had_icu
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.hadm_id = icu.hadm_id
    GROUP BY adm.hadm_id
),

icu_los AS (
    -- Calculate ICU LOS for admissions with ICU stays
    SELECT hadm_id, MAX(los) AS max_icu_los
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    GROUP BY hadm_id
),

los_data AS (
    -- Compute LOS for each admission: ICU patients use ICU LOS, non-ICU use hospital LOS
    SELECT adm.hadm_id,
           icu.had_icu,
           CASE
               WHEN icu.had_icu = 1 THEN icu_los.max_icu_los
               ELSE DATE_DIFF(adm.dischtime, adm.admittime, DAY)
           END AS los
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN icu_status icu
        ON adm.hadm_id = icu.hadm_id
    LEFT JOIN icu_los
        ON adm.hadm_id = icu_los.hadm_id
    INNER JOIN cohort
        ON adm.hadm_id = cohort.hadm_id
),

los_quartiles AS (
    -- Compute quartiles for LOS within ICU and non-ICU groups
    SELECT hadm_id,
           had_icu,
           los,
           NTILE(4) OVER (PARTITION BY had_icu ORDER BY los) AS quartile
    FROM los_data
),

mortality AS (
    -- In-hospital mortality
    SELECT adm.hadm_id,
           adm.hospital_expire_flag AS mortality
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN cohort
        ON adm.hadm_id = cohort.hadm_id
),

ventilation AS (
    -- Mechanical ventilation during admission
    SELECT hadm_id,
           COUNT(DISTINCT stay_id) > 0 AS vent_used
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
    WHERE itemid IN (
        227194, -- Ventilator
        225792, -- Invasive Ventilation
        225794  -- Non-Invasive Ventilation
    )
    GROUP BY hadm_id
),

vasopressors AS (
    -- Vasopressors during admission
    SELECT hadm_id,
           COUNT(DISTINCT stay_id) > 0 AS vasopressor_used
    FROM `physionet-data.mimiciv_3_1_icu.inputevents`
    WHERE itemid IN (
        221906, -- Norepinephrine
        221289, -- Epinephrine
        222315  -- Vasopressin
    )
    GROUP BY hadm_id
),

rrt AS (
    -- Renal Replacement Therapy during admission
    SELECT hadm_id,
           COUNT(DISTINCT stay_id) > 0 AS rrt_used
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
    WHERE itemid IN (
        225802, -- CRRT
        225803, -- Hemodialysis
        225809  -- Dialysis - other
    )
    GROUP BY hadm_id
),

combined AS (
    -- Combine all data
    SELECT q.hadm_id,
           q.had_icu,
           q.quartile,
           m.mortality,
           COALESCE(v.vent_used, FALSE) AS vent_used,
           COALESCE(vs.vasopressor_used, FALSE) AS vasopressor_used,
           COALESCE(r.rrt_used, FALSE) AS rrt_used
    FROM los_quartiles q
    INNER JOIN mortality m
        ON q.hadm_id = m.hadm_id
    LEFT JOIN ventilation v
        ON q.hadm_id = v.hadm_id
    LEFT JOIN vasopressors vs
        ON q.hadm_id = vs.hadm_id
    LEFT JOIN rrt r
        ON q.hadm_id = r.hadm_id
),

aggregated AS (
    -- Aggregate by ICU status and quartile
    SELECT had_icu,
           quartile,
           COUNT(*) AS n_patients,
           SUM(mortality) AS n_mortality,
           AVG(CAST(mortality AS FLOAT64)) * 100 AS mortality_percent,
           AVG(CAST(vent_used AS INT64)) * 100 AS vent_percent,
           AVG(CAST(vasopressor_used AS INT64)) * 100 AS vasopressor_percent,
           AVG(CAST(rrt_used AS INT64)) * 100 AS rrt_percent
    FROM combined
    GROUP BY had_icu, quartile
),

q1_mortality AS (
    -- Get mortality for Q1 to compute relative risk
    SELECT had_icu,
           mortality_percent AS q1_mortality
    FROM aggregated
    WHERE quartile = 1
)

-- Final output: absolute mortality, relative mortality (vs Q1), and treatment percentages
SELECT a.had_icu AS icu_group,
       a.quartile,
       a.n_patients,
       a.mortality_percent AS mortality_absolute,
       (a.mortality_percent - q1.q1_mortality) AS mortality_relative_to_q1,
       a.vent_percent,
       a.vasopressor_percent,
       a.rrt_percent
FROM aggregated a
LEFT JOIN q1_mortality q1
    ON a.had_icu = q1.had_icu
ORDER BY a.had_icu, a.quartile;