WITH cohort AS (
    SELECT 
        p.subject_id, 
        p.gender, 
        p.anchor_age,
        i.hadm_id,
        i.stay_id,
        i.intime,
        i.outtime,
        i.los AS icu_los,
        adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON i.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON i.hadm_id = adm.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON i.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 78 AND 88
        AND d.long_title LIKE '%hyperosmolarity%'
        AND (d.icd_code = 'E11.00' OR d.icd_code = 'E13.00')
),
vitals AS (
    SELECT 
        c.stay_id,
        ce.itemid,
        di.label,
        di.lownormalvalue,
        di.highnormalvalue,
        ce.valuenum,
        -- Check if the value is abnormal
        CASE WHEN ce.valuenum < di.lownormalvalue OR ce.valuenum > di.highnormalvalue THEN 1 ELSE 0 END AS is_abnormal
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON c.stay_id = ce.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
        ON ce.itemid = di.itemid
    WHERE ce.itemid IN (220045, 220181, 220210)  -- HR, MAP, RR
        AND ce.valuenum IS NOT NULL
        AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
),
vital_stats AS (
    SELECT 
        stay_id,
        itemid,
        COUNT(*) AS n_measurements,
        AVG(valuenum) AS mean_value,
        STDDEV(valuenum) AS sd_value,
        STDDEV(valuenum) / AVG(valuenum) AS cv,
        SUM(is_abnormal) AS abnormal_count
    FROM vitals
    GROUP BY stay_id, itemid
),
cv_sum_per_stay AS (
    SELECT 
        stay_id,
        SUM(cv) AS cv_sum,
        SUM(abnormal_count) AS total_abnormal_vitals
    FROM vital_stats
    GROUP BY stay_id
),
with_quantiles AS (
    SELECT 
        c.*,
        cs.cv_sum,
        cs.total_abnormal_vitals,
        NTILE(4) OVER (ORDER BY cs.cv_sum) AS quartile,
        NTILE(10) OVER (ORDER BY cs.cv_sum) AS decile
    FROM cohort c
    INNER JOIN cv_sum_per_stay cs
        ON c.stay_id = cs.stay_id
)
SELECT 
    stay_id,
    cv_sum AS stay_instability_score,
    decile,
    total_abnormal_vitals AS abnormal_vital_count,
    icu_los,
    hospital_expire_flag AS in_hospital_mortality
FROM with_quantiles
WHERE quartile = 4  -- Top quartile
ORDER BY stay_instability_score DESC;