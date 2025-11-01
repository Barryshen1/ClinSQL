WITH base_patients AS (
    SELECT
        p.subject_id,
        a.hadm_id,
        a.gender,
        a.anchor_age,
        a.hospital_expire_flag,
        i.stay_id,
        i.intime,
        i.los
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
        ON a.hadm_id = i.hadm_id
    WHERE a.gender = 'F'
      AND a.anchor_age BETWEEN 55 AND 65
      AND i.first_careunit IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY a.hadm_id
        ORDER BY i.intime
    ) = 1  -- first ICU stay per admission
),
pneumonia_diagnoses AS (
    SELECT
        d.subject_id,
        d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
    WHERE (d.icd_version = 9 AND d.icd_code BETWEEN '480' AND '488')
       OR (d.icd_version = 10 AND d.icd_code LIKE 'J1%')
),
vital_sign_itemids AS (
    SELECT
        itemid,
        label
    FROM `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE category = 'Vital Signs'
      AND (label LIKE '%Heart Rate%'
           OR label LIKE '%Systolic BP%'
           OR label LIKE '%Diastolic BP%'
           OR label LIKE '%Respiratory Rate%'
           OR label LIKE '%Temperature%')
),
hourly_vitals AS (
    SELECT
        b.subject_id,
        b.hadm_id,
        b.stay_id,
        b.intime,
        hour,
        vsi.label,
        (SELECT valuenum FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
         WHERE c.subject_id = b.subject_id
           AND c.hadm_id = b.hadm_id
           AND c.stay_id = b.stay_id
           AND c.itemid = vsi.itemid
           AND c.charttime BETWEEN TIMESTAMP_ADD(b.intime, INTERVAL hour HOUR)
                               AND TIMESTAMP_ADD(b.intime, INTERVAL hour + 1 HOUR)
         ORDER BY c.charttime DESC
         LIMIT 1) AS valuenum
    FROM base_patients b
    CROSS JOIN vital_sign_itemids vsi
    CROSS JOIN UNNEST(GENERATE_ARRAY(0, 23)) AS hour
    WHERE EXISTS (
        SELECT 1
        FROM pneumonia_diagnoses pd
        WHERE pd.subject_id = b.subject_id
          AND pd.hadm_id = b.hadm_id
    )
),
pivoted_vitals AS (
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        intime,
        hour,
        MAX(IF(label = 'Heart Rate', valuenum, NULL)) AS hr,
        MAX(IF(label = 'Systolic BP', valuenum, NULL)) AS sbp,
        MAX(IF(label = 'Diastolic BP', valuenum, NULL)) AS dbp,
        MAX(IF(label = 'Respiratory Rate', valuenum, NULL)) AS rr,
        MAX(IF(label = 'Temperature', valuenum, NULL)) AS temp
    FROM hourly_vitals
    GROUP BY subject_id, hadm_id, stay_id, intime, hour
),
instability_score AS (
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        SUM(
            COALESCE(ABS(hr - LAG(hr) OVER w), 0) +
            COALESCE(ABS(sbp - LAG(sbp) OVER w), 0) +
            COALESCE(ABS(dbp - LAG(dbp) OVER w), 0) +
            COALESCE(ABS(rr - LAG(rr) OVER w), 0) +
            COALESCE(ABS(temp - LAG(temp) OVER w), 0)
        ) AS instability_score
    FROM pivoted_vitals
    WINDOW w AS (PARTITION BY subject_id, hadm_id, stay_id ORDER BY hour)
    GROUP BY subject_id, hadm_id, stay_id
),
cohort AS (
    SELECT
        b.subject_id,
        b.hadm_id,
        b.stay_id,
        b.los,
        b.hospital_expire_flag,
        i.instability_score
    FROM base_patients b
    INNER JOIN pneumonia_diagnoses pd
        ON b.subject_id = pd.subject_id
        AND b.hadm_id = pd.hadm_id
    LEFT JOIN instability_score i
        ON b.subject_id = i.subject_id
        AND b.hadm_id = i.hadm_id
        AND b.stay_id = i.stay_id
    WHERE i.instability_score IS NOT NULL
),
percentile_calc AS (
    SELECT
        instability_score,
        PERCENT_RANK() OVER (ORDER BY instability_score) AS percentile
    FROM cohort
),
given_score_percentile AS (
    SELECT
        (SELECT percentile FROM percentile_calc
         WHERE instability_score = 60) AS given_score_percentile
),
top_decile AS (
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        los,
        hospital_expire_flag,
        instability_score
    FROM cohort
    WHERE instability_score >= (
        SELECT APPROX_QUANTILES(instability_score, 10)[OFFSET(9)]
        FROM cohort
    )
),
top_decile_stats AS (
    SELECT
        AVG(los) AS avg_los,
        AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
    FROM top_decile
)
SELECT
    (SELECT given_score_percentile FROM given_score_percentile) AS given_score_percentile,
    (SELECT avg_los FROM top_decile_stats) AS avg_los_top_decile,
    (SELECT mortality_rate FROM top_decile_stats) AS mortality_rate_top_decile
FROM cohort
LIMIT 1;