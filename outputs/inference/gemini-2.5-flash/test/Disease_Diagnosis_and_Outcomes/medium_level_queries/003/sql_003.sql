WITH patient_cohort AS (
    -- Select eligible patients: men aged 44-54 at admission
    SELECT
        p.subject_id,
        p.gender,
        p.anchor_age,
        p.anchor_year,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.deathtime,
        a.hospital_expire_flag,
        p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS admission_age
    FROM
        `physionet-data.mimiciv_3_1_hosp`.patients p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.admissions a
        ON p.subject_id = a.subject_id
    WHERE
        p.gender = 'M'
        AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 44 AND 54
),
stroke_classification AS (
    -- Classify admissions into Ischemic or Hemorrhagic stroke based on ICD-10 codes.
    -- Prioritize Hemorrhagic if both types are present for a given admission.
    SELECT
        pc.subject_id,
        pc.hadm_id,
        pc.admittime,
        pc.dischtime,
        pc.deathtime,
        pc.hospital_expire_flag,
        pc.admission_age,
        COALESCE(
            MAX(CASE WHEN d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%' THEN 'Hemorrhagic Stroke' END),
            MAX(CASE WHEN d.icd_code LIKE 'I63%' THEN 'Ischemic Stroke' END)
        ) AS stroke_type,
        DATETIME_DIFF(COALESCE(pc.deathtime, pc.dischtime), pc.admittime, DAY) AS los_days
    FROM
        patient_cohort pc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
        ON pc.subject_id = d.subject_id AND pc.hadm_id = d.hadm_id
    WHERE
        d.icd_version = 10 -- Ensure ICD-10 only
        AND (
            d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%' -- Hemorrhagic
            OR d.icd_code LIKE 'I63%' -- Ischemic
        )
    GROUP BY
        pc.subject_id, pc.hadm_id, pc.admittime, pc.dischtime, pc.deathtime, pc.hospital_expire_flag, pc.admission_age
    HAVING
        COALESCE(
            MAX(CASE WHEN d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%' THEN 'Hemorrhagic Stroke' END),
            MAX(CASE WHEN d.icd_code LIKE 'I63%' THEN 'Ischemic Stroke' END)
        ) IS NOT NULL -- Exclude admissions that do not clearly fit one category.
),
comorbidity_severity AS (
    -- Determine comorbidity category based on DRG severity.
    SELECT
        s.hadm_id,
        CASE
            WHEN drg.drg_severity = 'Moderate' THEN 'Low Comorbidity'
            WHEN drg.drg_severity = 'Major' THEN 'Medium Comorbidity'
            WHEN drg.drg_severity = 'Extensive' THEN 'High Comorbidity'
            ELSE 'Unknown Comorbidity' -- Handle other/null DRG severities
        END AS comorbidity_category
    FROM
        stroke_classification s
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp`.drgcodes drg
        ON s.hadm_id = drg.hadm_id
    QUALIFY ROW_NUMBER() OVER (PARTITION BY s.hadm_id ORDER BY
        CASE drg.drg_severity
            WHEN 'Extensive' THEN 3
            WHEN 'Major' THEN 2
            WHEN 'Moderate' THEN 1
            ELSE 0
        END DESC -- Prioritize higher severity if multiple DRGs exist
    ) = 1
),
-- CTE to pre-filter itemids for Mechanical Ventilation from d_items
relevant_vent_itemids AS (
    SELECT CAST(itemid AS INT64) AS itemid FROM `physionet-data.mimiciv_3_1_icu`.d_items
    WHERE CAST(itemid AS INT64) IN (
        224687, -- Ventilator Mode
        224690, -- Ventilator Mode Volume
        224684, -- Ventilator Rate (Set)
        220339, -- Ventilator PaCO2 (mm Hg)
        220338, -- Ventilator PaO2 (mm Hg)
        220179, -- Respiratory Rate (Set)
        224700, -- Rate (Set)
        220210, -- Respiratory Rate
        224697, -- Inspiratory Time
        227288, -- Active preset mode
        224734, -- Inspiratory pressure
        224731, -- Pressure Support
        223849  -- Ventilation Kind
    )
    OR (LOWER(label) LIKE '%ventilation%' AND LOWER(label) NOT LIKE '%non-invasive%')
    OR LOWER(label) LIKE '%ventilator%'
    OR LOWER(label) LIKE '%mv mode%'
    OR LOWER(label) LIKE '%peep%'
    OR LOWER(category) LIKE '%ventilation%'
),
-- CTE to pre-filter itemids for Vasopressors from d_items
relevant_vaso_itemids AS (
    SELECT CAST(itemid AS INT64) AS itemid FROM `physionet-data.mimiciv_3_1_icu`.d_items
    WHERE CAST(itemid AS INT64) IN (
        221906, -- Norepinephrine
        221662, -- Dopamine
        221289, -- Epinephrine
        222315, -- Phenylephrine
        222370, -- Vasopressin
        222049, -- Dobutamine
        221749  -- Milrinone (inotrope)
    )
    OR LOWER(label) LIKE '%norepinephrine%'
    OR LOWER(label) LIKE '%epinephrine%'
    OR LOWER(label) LIKE '%phenylephrine%'
    OR LOWER(label) LIKE '%dopamine%'
    OR LOWER(label) LIKE '%vasopressin%'
    OR LOWER(label) LIKE '%dobutamine%'
    OR LOWER(label) LIKE '%milrinone%'
    OR LOWER(category) LIKE '%vaso%'
),
-- CTE to pre-filter itemids for RRT from d_items
relevant_rrt_itemids AS (
    SELECT CAST(itemid AS INT64) AS itemid FROM `physionet-data.mimiciv_3_1_icu`.d_items
    WHERE CAST(itemid AS INT64) IN (
        225792, -- Dialysis Total Duration
        225802, -- Dialysis Type
        227299, -- CRRT Filter (post)
        225389, -- Continuous Renal Replacement Therapy (CRRT)
        224191  -- Haemodialysis session started
    )
    OR LOWER(label) LIKE '%dialysis%'
    OR LOWER(label) LIKE '%crrt%'
    OR LOWER(label) LIKE '%rrt%'
),
admissions_with_interventions AS (
    -- Link hospital admissions to ICU stays and identify specific interventions per admission.
    SELECT
        sc.subject_id,
        sc.hadm_id,
        sc.stroke_type,
        cs.comorbidity_category,
        sc.los_days,
        sc.hospital_expire_flag,
        -- Flag for Mechanical Ventilation (1 if *any* ICU stay within this admission had vent)
        MAX(CASE WHEN vent_stays.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS admission_has_mech_vent,
        -- Flag for Vasopressors (1 if *any* ICU stay within this admission had vasopressor)
        MAX(CASE WHEN vaso_stays.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS admission_has_vasopressor,
        -- Flag for RRT (1 if *any* ICU stay within this admission had RRT)
        MAX(CASE WHEN rrt_stays.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS admission_has_rrt
    FROM
        stroke_classification sc
    INNER JOIN
        comorbidity_severity cs
        ON sc.hadm_id = cs.hadm_id
    LEFT JOIN
        `physionet-data.mimiciv_3_1_icu`.icustays icu
        ON sc.subject_id = icu.subject_id AND sc.hadm_id = icu.hadm_id

    -- Subquery to find ICU stays with Mechanical Ventilation
    LEFT JOIN (
        SELECT DISTINCT ie.stay_id
        FROM `physionet-data.mimiciv_3_1_icu`.chartevents ie
        -- Explicitly cast di.itemid to INT64 for comparison with ie.itemid
        INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di ON ie.itemid = CAST(di.itemid AS INT64)
        WHERE
            ie.itemid IN (SELECT itemid FROM relevant_vent_itemids) -- Use pre-filtered itemids (now guaranteed INT64)
            OR (LOWER(di.label) LIKE '%fio2%' AND ie.valuenum > 21) -- Fio2 condition here as it requires ie.valuenum
    ) AS vent_stays
        ON icu.stay_id = vent_stays.stay_id
        
    -- Subquery to find ICU stays with Vasopressors
    LEFT JOIN (
        SELECT DISTINCT ie.stay_id
        FROM `physionet-data.mimiciv_3_1_icu`.inputevents ie
        WHERE ie.itemid IN (SELECT itemid FROM relevant_vaso_itemids) -- Use pre-filtered itemids (now guaranteed INT64)
    ) AS vaso_stays
        ON icu.stay_id = vaso_stays.stay_id

    -- Subquery to find ICU stays with RRT
    LEFT JOIN (
        SELECT DISTINCT ie.stay_id
        FROM `physionet-data.mimiciv_3_1_icu`.chartevents ie
        WHERE ie.itemid IN (SELECT itemid FROM relevant_rrt_itemids) -- Use pre-filtered itemids (now guaranteed INT64)
    ) AS rrt_stays
        ON icu.stay_id = rrt_stays.stay_id
    WHERE cs.comorbidity_category != 'Unknown Comorbidity' -- Filter out unknown comorbidity
    GROUP BY
        sc.subject_id, sc.hadm_id, sc.stroke_type, cs.comorbidity_category, sc.los_days, sc.hospital_expire_flag
)
SELECT
    awi.stroke_type,
    CASE
        WHEN awi.los_days <= 5 THEN 'LOS <= 5 Days'
        ELSE 'LOS > 5 Days'
    END AS los_category,
    awi.comorbidity_category,
    COUNT(awi.hadm_id) AS total_admissions,
    ROUND(SUM(awi.hospital_expire_flag) * 100.0 / COUNT(awi.hadm_id), 2) AS mortality_percentage,
    -- Calculate median LOS. Using BigQuery's PERCENTILE_CONT as an aggregate window function.
    PERCENTILE_CONT(awi.los_days, 0.5) OVER (PARTITION BY awi.stroke_type,
        CASE WHEN awi.los_days <= 5 THEN 'LOS <= 5 Days' ELSE 'LOS > 5 Days' END,
        awi.comorbidity_category ORDER BY awi.los_days ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS median_los_days,
    -- Percentage of admissions with mechanical ventilation
    ROUND(SUM(awi.admission_has_mech_vent) * 100.0 / COUNT(awi.hadm_id), 2) AS percent_mech_vent,
    -- Percentage of admissions with vasopressors
    ROUND(SUM(awi.admission_has_vasopressor) * 100.0 / COUNT(awi.hadm_id), 2) AS percent_vasopressors,
    -- Percentage of admissions with RRT
    ROUND(SUM(awi.admission_has_rrt) * 100.0 / COUNT(awi.hadm_id), 2) AS percent_rrt
FROM
    admissions_with_interventions awi
GROUP BY
    awi.stroke_type,
    los_category,
    awi.comorbidity_category
ORDER BY
    awi.stroke_type,
    los_category,
    awi.comorbidity_category;