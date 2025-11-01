WITH eligible_patients AS (
    SELECT
        p.subject_id,
        p.gender,
        p.anchor_age,
        p.anchor_year,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 82 AND 92
        AND a.hospital_expire_flag IS NOT NULL
),
first_icu_stays AS (
    SELECT
        i.subject_id,
        i.hadm_id,
        i.stay_id,
        i.intime,
        i.outtime,
        ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN eligible_patients e
        ON i.subject_id = e.subject_id
        AND i.hadm_id = e.hadm_id
    WHERE i.stay_id IS NOT NULL
),
arf_stays AS (
    SELECT
        f.subject_id,
        f.hadm_id,
        f.stay_id,
        f.intime,
        f.outtime,
        d.icd_code
    FROM first_icu_stays f
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON f.subject_id = d.subject_id
        AND f.hadm_id = d.hadm_id
    WHERE d.icd_version = 10
        AND d.icd_code IN (
            'J96.9', 'J98.9', 'J95.9', 'J96.8', 'J96.0', 'J96.1', 'J96.2', 'J96.3',
            'J96.4', 'J96.5', 'J96.6', 'J96.7', 'J98.4'
        )
),
general_icu_stays AS (
    SELECT
        f.subject_id,
        f.hadm_id,
        f.stay_id,
        f.intime,
        f.outtime,
        e.hospital_expire_flag
    FROM first_icu_stays f
    INNER JOIN eligible_patients e
        ON f.subject_id = e.subject_id
        AND f.hadm_id = e.hadm_id
),
time_grid AS (
    SELECT
        stay_id,
        intime,
        TIMESTAMP_ADD(intime, INTERVAL hour HOUR) AS hour_start,
        TIMESTAMP_ADD(intime, INTERVAL hour+1 HOUR) AS hour_end
    FROM general_icu_stays,
    UNNEST(GENERATE_ARRAY(0, 71)) AS hour
),
vitals AS (
    SELECT
        ce.subject_id,
        ce.hadm_id,
        ce.stay_id,
        ce.charttime,
        ce.valuenum,
        di.label,
        di.itemid
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
        ON ce.itemid = di.itemid
    WHERE di.label IN ('Mean Arterial Pressure', 'Heart Rate')
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0
),
hourly_burden AS (
    SELECT
        tg.stay_id,
        tg.hour_start,
        tg.hour_end,
        MAX(CASE WHEN v.label = 'Mean Arterial Pressure' AND v.valuenum < 65 THEN 1 ELSE 0 END) AS map_burden,
        MAX(CASE WHEN v.label = 'Heart Rate' AND v.valuenum > 100 THEN 1 ELSE 0 END) AS hr_burden,
        MAX(CASE WHEN (v.label = 'Mean Arterial Pressure' AND v.valuenum < 65) OR (v.label = 'Heart Rate' AND v.valuenum > 100) THEN 1 ELSE 0 END) AS composite_burden
    FROM time_grid tg
    LEFT JOIN vitals v
        ON tg.stay_id = v.stay_id
        AND v.charttime BETWEEN tg.hour_start AND tg.hour_end
    GROUP BY tg.stay_id, tg.hour_start, tg.hour_end
),
stay_burden AS (
    SELECT
        stay_id,
        SUM(composite_burden) AS instability_score
    FROM hourly_burden
    GROUP BY stay_id
),
arf_stats AS (
    SELECT
        APPROX_QUANTILES(instability_score, 100) AS arf_quantiles
    FROM stay_burden
    WHERE stay_id IN (SELECT stay_id FROM arf_stays)
),
comparison_stats AS (
    SELECT
        CASE WHEN s.stay_id IN (SELECT stay_id FROM arf_stays) THEN 'ARF' ELSE 'Non-ARF' END AS group_type,
        AVG(sb.instability_score) AS avg_instability,
        AVG(EXTRACT(HOUR FROM TIMESTAMP_DIFF(g.outtime, g.intime, HOUR))) AS avg_los_hours,
        AVG(CAST(g.hospital_expire_flag AS INT)) AS mortality_rate
    FROM general_icu_stays g
    LEFT JOIN stay_burden sb
        ON g.stay_id = sb.stay_id
    GROUP BY group_type
)
SELECT
    (SELECT arf_quantiles[OFFSET(24)] FROM arf_stats) AS arf_p25,
    (SELECT arf_quantiles[OFFSET(49)] FROM arf_stats) AS arf_median,
    (SELECT arf_quantiles[OFFSET(74)] FROM arf_stats) AS arf_p75,
    (SELECT arf_quantiles[OFFSET(74)] - arf_quantiles[OFFSET(24)] FROM arf_stats) AS arf_iqr,
    cs.group_type,
    cs.avg_instability,
    cs.avg_los_hours,
    cs.mortality_rate
FROM comparison_stats cs;