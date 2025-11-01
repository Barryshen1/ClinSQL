WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
),

meds_first_24hr AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    COUNT(DISTINCT e.medication) AS med_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN
    cohort c
  ON
    e.hadm_id = c.hadm_id
  WHERE
    e.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY
    e.subject_id, e.hadm_id
),

qt_meds AS (
  SELECT DISTINCT medication
  FROM UNNEST([
    'Amiodarone', 'Sotalol', 'Dofetilide', 'Ibutilide', 'Quinidine',
    'Procainamide', 'Disopyramide', 'Flecainide', 'Propafenone'
  ]) AS medication
),

bleed_meds AS (
  SELECT DISTINCT medication
  FROM UNNEST([
    'Warfarin', 'Heparin', 'Enoxaparin', 'Rivaroxaban', 'Apixaban',
    'Dabigatran', 'Clopidogrel', 'Prasugrel', 'Ticagrelor'
  ]) AS medication
),

interaction_flags AS (
  SELECT
    m.subject_id,
    m.hadm_id,
    m.med_count,
    CASE WHEN qt_drugs.cnt > 0 THEN 1 ELSE 0 END AS has_qt_drugs,
    CASE WHEN bleed_drugs.cnt > 0 THEN 1 ELSE 0 END AS has_bleed_drugs
  FROM
    meds_first_24hr m
  LEFT JOIN (
    SELECT
      e.hadm_id,
      COUNT(*) AS cnt
    FROM
      `physionet-data.mimiciv_3_1_hosp.emar` e
    JOIN qt_meds q ON e.medication = q.medication
    WHERE
      e.charttime BETWEEN (
        SELECT admittime FROM cohort c WHERE c.hadm_id = e.hadm_id
      ) AND DATETIME_ADD((
        SELECT admittime FROM cohort c WHERE c.hadm_id = e.hadm_id
      ), INTERVAL 24 HOUR)
    GROUP BY e.hadm_id
  ) qt_drugs ON m.hadm_id = qt_drugs.hadm_id
  LEFT JOIN (
    SELECT
      e.hadm_id,
      COUNT(*) AS cnt
    FROM
      `physionet-data.mimiciv_3_1_hosp.emar` e
    JOIN bleed_meds b ON e.medication = b.medication
    WHERE
      e.charttime BETWEEN (
        SELECT admittime FROM cohort c WHERE c.hadm_id = e.hadm_id
      ) AND DATETIME_ADD((
        SELECT admittime FROM cohort c WHERE c.hadm_id = e.hadm_id
      ), INTERVAL 24 HOUR)
    GROUP BY e.hadm_id
  ) bleed_drugs ON m.hadm_id = bleed_drugs.hadm_id
),

complexity_with_ranks AS (
  SELECT
    i.*,
    c.los_days,
    c.hospital_expire_flag,
    PERCENT_RANK() OVER (ORDER BY i.med_count) AS med_complexity_percentile,
    NTILE(4) OVER (ORDER BY i.med_count) AS med_complexity_quartile
  FROM
    interaction_flags i
  JOIN
    cohort c
  ON
    i.hadm_id = c.hadm_id
)

SELECT
  'QT-Prolonging' AS group_type,
  COUNT(*) AS patient_count,
  AVG(med_count) AS avg_med_count,
  AVG(med_complexity_percentile) AS avg_percentile,
  AVG(los_days) AS avg_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM
  complexity_with_ranks
WHERE
  has_qt_drugs = 1

UNION ALL

SELECT
  'Bleeding Risk' AS group_type,
  COUNT(*) AS patient_count,
  AVG(med_count) AS avg_med_count,
  AVG(med_complexity_percentile) AS avg_percentile,
  AVG(los_days) AS avg_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM
  complexity_with_ranks
WHERE
  has_bleed_drugs = 1

UNION ALL

SELECT
  'General Inpatients' AS group_type,
  COUNT(*) AS patient_count,
  AVG(med_count) AS avg_med_count,
  AVG(med_complexity_percentile) AS avg_percentile,
  AVG(los_days) AS avg_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM
  complexity_with_ranks

UNION ALL

SELECT
  'Top Quartile (All)' AS group_type,
  COUNT(*) AS patient_count,
  AVG(med_count) AS avg_med_count,
  NULL AS avg_percentile,
  AVG(los_days) AS avg_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM
  complexity_with_ranks
WHERE
  med_complexity_quartile = 4;