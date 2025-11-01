WITH Admissions_Age_Gender AS (
    -- Base cohort: Male ICU patients aged 81-91
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.deathtime,
        ad.hospital_expire_flag,
        icu.stay_id,
        icu.intime,
        icu.outtime,
        icu.loS,
        p.gender,
        p.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON ad.subject_id = icu.subject_id AND ad.hadm_id = icu.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 81 AND 91
),
HFNC_Patients AS (
    -- Identify patients who received HFNC in the first 48 hours of ICU stay
    SELECT DISTINCT
        a.subject_id,
        a.hadm_id,
        a.stay_id,
        a.intime,
        a.outtime,
        a.loS,
        a.hospital_expire_flag
    FROM Admissions_Age_Gender a
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON a.subject_id = ce.subject_id AND a.stay_id = ce.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
        ON ce.itemid = di.itemid
    WHERE
        ce.charttime BETWEEN a.intime AND TIMESTAMP_ADD(a.intime, INTERVAL 48 HOUR)
        AND (
            LOWER(di.label) LIKE '%high flow nasal cannula%'
            OR LOWER(di.label) LIKE '%hfnc%'
            -- Specific itemids for HFNC usage/settings, ensuring a valid measurement or status
            OR (di.itemid = 227091 AND LOWER(ce.value) = 'active') -- High Flow NC use: active
            OR (di.itemid = 227287 AND LOWER(ce.value) LIKE '%optiflow%') -- HFNC cannula type: Optiflow, Vapotherm
            OR (di.itemid = 226786 AND ce.valuenum IS NOT NULL AND ce.valuenum > 0) -- High Flow NC settings: ensure flow > 0
            OR (di.itemid = 227284 AND LOWER(ce.value) LIKE '%hfnc%') -- Nasal Cannula w/humidity. (sometimes used for HFNC settings if no specific HFNC itemid is logged)
            -- Add other relevant itemids if known for HFNC, e.g., oxygen flow rate settings if coupled with HFNC delivery method
        )
),
First_48h_Vitals_Labs AS (
    -- Collect vital signs and labs for the first 48 hours for HFNC patients
    SELECT
        h.subject_id,
        h.hadm_id,
        h.stay_id,
        h.intime,
        -- Max Heart Rate (itemid 220045)
        MAX(CASE WHEN ce.itemid = 220045 AND ce.valuenum IS NOT NULL AND ce.valuenum > 0 THEN ce.valuenum END) AS max_hr,
        -- Min Mean Arterial Pressure (itemid 220052)
        MIN(CASE WHEN ce.itemid = 220052 AND ce.valuenum IS NOT NULL AND ce.valuenum > 0 THEN ce.valuenum END) AS min_map,
        -- Max Lactate (itemid 50813)
        MAX(CASE WHEN le.itemid = 50813 AND le.valuenum IS NOT NULL AND le.valuenum > 0 THEN le.valuenum END) AS max_lactate
    FROM HFNC_Patients h
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON h.subject_id = ce.subject_id AND h.stay_id = ce.stay_id
        AND ce.charttime BETWEEN h.intime AND TIMESTAMP_ADD(h.intime, INTERVAL 48 HOUR) AND ce.warning IS DISTINCT FROM 1
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON h.subject_id = le.subject_id AND h.hadm_id = le.hadm_id
        AND le.charttime BETWEEN h.intime AND TIMESTAMP_ADD(h.intime, INTERVAL 48 HOUR) AND le.comments IS NULL
    GROUP BY h.subject_id, h.hadm_id, h.stay_id, h.intime
    HAVING MAX(CASE WHEN ce.itemid = 220045 AND ce.valuenum IS NOT NULL AND ce.valuenum > 0 THEN 1 END) IS NOT NULL
        OR MIN(CASE WHEN ce.itemid = 220052 AND ce.valuenum IS NOT NULL AND ce.valuenum > 0 THEN 1 END) IS NOT NULL
        OR MAX(CASE WHEN le.itemid = 50813 AND le.valuenum IS NOT NULL AND le.valuenum > 0 THEN 1 END) IS NOT NULL
),
Calculated_Scores AS (
    -- Calculate the hypothetical instability score.
    -- This is a simplified definition based on common clinical understanding *due to absence of explicit definition*
    SELECT
        a.subject_id,
        a.hadm_id,
        a.stay_id,
        a.loS,
        a.hospital_expire_flag,
        -- Calculate individual component scores (0-100 where 100 is most unstable)
        -- Heart Rate (60-120 normal range, >120 unstable)
        CASE
            WHEN v.max_hr IS NULL THEN 0 -- A neutral score if not recorded
            WHEN v.max_hr >= 120 THEN 100
            WHEN v.max_hr <= 60 THEN 0 -- For this score definition, lower HR is not considered unstable
            ELSE (v.max_hr - 60) * 100.0 / (120 - 60)
        END AS score_hr,
        -- Mean Arterial Pressure (60-90 normal range, <60 unstable)
        CASE
            WHEN v.min_map IS NULL THEN 0
            WHEN v.min_map <= 60 THEN 100
            WHEN v.min_map >= 90 THEN 0 -- For this score definition, higher MAP is not considered unstable
            ELSE (90 - v.min_map) * 100.0 / (90 - 60)
        END AS score_map,
        -- Lactate (1-4 mmol/L normal/mildly elevated, >4 mmol/L unstable)
        CASE
            WHEN v.max_lactate IS NULL THEN 0
            WHEN v.max_lactate >= 4 THEN 100
            WHEN v.max_lactate <= 1 THEN 0
            ELSE (v.max_lactate - 1) * 100.0 / (4 - 1)
        END AS score_lactate
    FROM HFNC_Patients a
    INNER JOIN First_48h_Vitals_Labs v -- Use INNER JOIN here to ensure we only score patients with gathered vitals/labs
        ON a.subject_id = v.subject_id AND a.stay_id = v.stay_id
),
Final_Scores AS (
    -- Combine individual scores into a composite average score
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        loS,
        hospital_expire_flag,
        (score_hr + score_map + score_lactate) / 3 AS instability_score
    FROM Calculated_Scores
),
Ranked_Scores AS (
    -- Calculate percentile ranks and decile for each patient
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        instability_score,
        loS,
        hospital_expire_flag,
        -- The percentile_rank_score is a value between 0 and 1, representing the rank of the current row within the ordered group.
        -- If a score of X is at `P` percentile rank, it means `P` percent of scores are less than or equal to X.
        PERCENT_RANK() OVER (ORDER BY instability_score) AS percentile_rank_score,
        -- NTILE(10) assigns a decile number (1-10) where 1 is the highest 10%
        NTILE(10) OVER (ORDER BY instability_score DESC) AS instability_decile
    FROM Final_Scores
    WHERE instability_score IS NOT NULL
)
-- Final Output
SELECT
    -- Percentile for a score of 85: The cumulative percentage of patients with a score less than or equal to 85.
    -- Use SAFE_DIVIDE to prevent "division by zero" if COUNT(*) is 0.
    SAFE_DIVIDE(COUNT(CASE WHEN rs.instability_score <= 85 THEN 1 END) * 100.0, COUNT(*)) AS percentile_for_score_85,
    -- Average ICU LOS for the top decile (highest instability scores)
    -- Use COALESCE to return 0 instead of NULL if the top decile is empty.
    COALESCE(AVG(CASE WHEN rs.instability_decile = 1 THEN rs.loS END), 0) AS avg_icu_los_top_decile_days,
    -- Hospital mortality percentage for the top decile
    -- Use COALESCE to return 0 instead of NULL if the top decile is empty, ensuring multiplication by 100.0 happens on a non-NULL.
    COALESCE(AVG(CASE WHEN rs.instability_decile = 1 THEN rs.hospital_expire_flag END), 0) * 100.0 AS hospital_mortality_top_decile_percent
FROM Ranked_Scores rs;