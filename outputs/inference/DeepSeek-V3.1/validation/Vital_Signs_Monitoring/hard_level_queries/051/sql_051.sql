WITH cohort AS (
    SELECT 
        ie.subject_id, 
        ie.hadm_id, 
        ie.stay_id,
        ie.intime, 
        ie.outtime,
        ie.los,
        p.gender,
        p.anchor_age,
        a.hospital_expire_flag,
        -- Identify ischemic stroke
        MAX(CASE 
            WHEN di.icd_code LIKE 'I63%' OR di.icd_code LIKE '433%' OR di.icd_code LIKE '434%' 
            THEN 1 ELSE 0 
        END) AS is_ischemic_stroke
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON ie.hadm_id = a.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ie.hadm_id = di.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 89 AND 99
    GROUP BY ie.subject_id, ie.hadm_id, ie.stay_id, ie.intime, ie.outtime, ie.los, p.gender, p.anchor_age, a.hospital_expire_flag
),

vitals AS (
    SELECT 
        c.stay_id,
        c.subject_id,
        c.hadm_id,
        ce.charttime,
        ce.itemid,
        ce.valuenum,
        -- Define normal ranges for common vitals
        CASE 
            WHEN ce.itemid IN (220045, 211) AND ce.valuenum < 60 THEN 1  -- HR brady
            WHEN ce.itemid IN (220045, 211) AND ce.valuenum > 100 THEN 1 -- HR tachy
            WHEN ce.itemid IN (220179, 51) AND ce.valuenum < 90 THEN 1   -- SBP low
            WHEN ce.itemid IN (220179, 51) AND ce.valuenum > 140 THEN 1  -- SBP high
            WHEN ce.itemid IN (220180, 8368) AND ce.valuenum < 60 THEN 1 -- DBP low
            WHEN ce.itemid IN (220180, 8368) AND ce.valuenum > 90 THEN 1 -- DBP high
            WHEN ce.itemid IN (220181, 456) AND ce.valuenum < 70 THEN 1  -- MAP low
            WHEN ce.itemid IN (220181, 456) AND ce.valuenum > 110 THEN 1 -- MAP high
            WHEN ce.itemid IN (220210, 618) AND ce.valuenum < 12 THEN 1  -- RR low
            WHEN ce.itemid IN (220210, 618) AND ce.valuenum > 20 THEN 1  -- RR high
            WHEN ce.itemid IN (220277, 646) AND ce.valuenum < 88 THEN 1  -- SpO2 low
            ELSE 0
        END AS is_abnormal
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON c.stay_id = ce.stay_id
    WHERE ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
        AND ce.valuenum IS NOT NULL
        AND ce.itemid IN (
            220045, 211,   -- Heart Rate
            220179, 51,    -- Systolic BP
            220180, 8368,  -- Diastolic BP
            220181, 456,   -- Mean BP
            220210, 618,   -- Respiratory Rate
            220277, 646    -- SpO2
        )
),

instability_calc AS (
    SELECT 
        sd.stay_id,
        -- Calculate average SD across vitals as composite instability
        AVG(sd.std_dev) AS instability_score,
        abn.abnormal_episodes
    FROM (
        SELECT 
            stay_id,
            STDDEV(valuenum) AS std_dev
        FROM vitals
        GROUP BY stay_id, itemid
    ) sd
    INNER JOIN (
        SELECT 
            stay_id, 
            SUM(is_abnormal) AS abnormal_episodes
        FROM vitals
        GROUP BY stay_id
    ) abn ON sd.stay_id = abn.stay_id
    GROUP BY sd.stay_id, abn.abnormal_episodes
),

cohort_instability AS (
    SELECT 
        c.*,
        COALESCE(i.instability_score, 0) AS instability_score,
        COALESCE(i.abnormal_episodes, 0) AS abnormal_episodes,
        -- Percentile and quartile calculations
        PERCENTILE_CONT(instability_score, 0.95) OVER() AS p95,
        PERCENTILE_CONT(instability_score, 0.75) OVER() AS q3
    FROM cohort c
    LEFT JOIN instability_calc i
        ON c.stay_id = i.stay_id
),

top_quartile AS (
    SELECT *
    FROM cohort_instability
    WHERE instability_score >= q3
)

SELECT 
    CASE 
        WHEN is_ischemic_stroke = 1 THEN 'Ischemic Stroke'
        ELSE 'General ICU'
    END AS group_name,
    COUNT(*) AS N,
    AVG(instability_score) AS mean_instability,
    AVG(abnormal_episodes) AS mean_abnormal_episodes,
    AVG(los * 24) AS mean_icu_los_hrs,
    AVG(hospital_expire_flag) AS mortality_rate
FROM top_quartile
GROUP BY is_ischemic_stroke
ORDER BY group_name;