WITH tf AS (
    SELECT 
        le.hadm_id,
        le.valuenum,
        ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di ON le.itemid = di.itemid
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON le.hadm_id = a.hadm_id
    WHERE LOWER(di.label) LIKE '%troponin t%'
        AND le.charttime >= a.admittime
)
SELECT 
    AVG(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS avg_los_days,
    AVG(CAST(a.hospital_expire_flag AS INT64)) AS mortality_rate
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
JOIN tf ON a.hadm_id = tf.hadm_id AND tf.rn = 1
WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 73 AND 83
    AND tf.valuenum > 0.01;