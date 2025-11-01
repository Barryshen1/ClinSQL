WITH eligible_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
    AND a.hadm_id IS NOT NULL
),
-- Gather device mentions from HCPCS short descriptions (hospital)
hcpcs_devices AS (
  SELECT
    hadm_id,
    subject_id,
    CASE
      WHEN LOWER(short_description) LIKE '%ecmo%' OR LOWER(short_description) LIKE '%extracorporeal%' THEN 'ECMO'
      WHEN (LOWER(short_description) LIKE '%intra%' AND LOWER(short_description) LIKE '%balloon%') OR LOWER(short_description) LIKE '%iabp%' THEN 'IABP'
      WHEN LOWER(short_description) LIKE '%impella%' THEN 'Impella'
      WHEN LOWER(short_description) LIKE '%tandem%' THEN 'TandemHeart'
      WHEN LOWER(short_description) LIKE '%ventricular assist%' OR LOWER(short_description) LIKE '%ventricular-assist%' OR LOWER(short_description) LIKE '%lvad%' OR LOWER(short_description) LIKE '%rvad%' OR LOWER(short_description) LIKE '%vad%' OR LOWER(short_description) LIKE '%bivad%' OR LOWER(short_description) LIKE '%heartmate%' THEN 'VAD'
      WHEN LOWER(short_description) LIKE '%assist%' OR LOWER(short_description) LIKE '%mechanical circulatory support%' THEN 'Other MCS'
      ELSE NULL
    END AS device
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
),
-- Gather device mentions from ICD procedure descriptions (hospital procedures_icd + d_icd_procedures)
icdproc_devices AS (
  SELECT
    p.hadm_id,
    p.subject_id,
    CASE
      WHEN LOWER(d.long_title) LIKE '%ecmo%' OR LOWER(d.long_title) LIKE '%extracorporeal%' THEN 'ECMO'
      WHEN (LOWER(d.long_title) LIKE '%intra%' AND LOWER(d.long_title) LIKE '%balloon%') OR LOWER(d.long_title) LIKE '%iabp%' THEN 'IABP'
      WHEN LOWER(d.long_title) LIKE '%impella%' THEN 'Impella'
      WHEN LOWER(d.long_title) LIKE '%tandem%' THEN 'TandemHeart'
      WHEN LOWER(d.long_title) LIKE '%ventricular assist%' OR LOWER(d.long_title) LIKE '%ventricular-assist%' OR LOWER(d.long_title) LIKE '%lvad%' OR LOWER(d.long_title) LIKE '%rvad%' OR LOWER(d.long_title) LIKE '%vad%' OR LOWER(d.long_title) LIKE '%bivad%' OR LOWER(d.long_title) LIKE '%heartmate%' THEN 'VAD'
      WHEN LOWER(d.long_title) LIKE '%assist%' OR LOWER(d.long_title) LIKE '%mechanical circulatory support%' THEN 'Other MCS'
      ELSE NULL
    END AS device
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
  ON
    p.icd_code = d.icd_code
    AND p.icd_version = d.icd_version
),
-- Gather device mentions from ICU procedureevents joined to d_items labels
icu_proc_devices AS (
  SELECT
    pe.hadm_id,
    pe.subject_id,
    CASE
      WHEN LOWER(di.label) LIKE '%ecmo%' OR LOWER(CAST(pe.value AS STRING)) LIKE '%ecmo%' OR LOWER(di.label) LIKE '%extracorporeal%' THEN 'ECMO'
      WHEN (LOWER(di.label) LIKE '%intra%' AND LOWER(di.label) LIKE '%balloon%')
           OR (LOWER(CAST(pe.value AS STRING)) LIKE '%intra%' AND LOWER(CAST(pe.value AS STRING)) LIKE '%balloon%')
           OR LOWER(di.label) LIKE '%iabp%' OR LOWER(CAST(pe.value AS STRING)) LIKE '%iabp%' THEN 'IABP'
      WHEN LOWER(di.label) LIKE '%impella%' OR LOWER(CAST(pe.value AS STRING)) LIKE '%impella%' THEN 'Impella'
      WHEN LOWER(di.label) LIKE '%tandem%' OR LOWER(CAST(pe.value AS STRING)) LIKE '%tandem%' THEN 'TandemHeart'
      WHEN LOWER(di.label) LIKE '%ventricular assist%' OR LOWER(di.label) LIKE '%ventricular-assist%' OR LOWER(di.label) LIKE '%lvad%' OR LOWER(di.label) LIKE '%rvad%' OR LOWER(di.label) LIKE '%vad%' OR LOWER(di.label) LIKE '%bivad%' OR LOWER(di.label) LIKE '%heartmate%'
           OR LOWER(CAST(pe.value AS STRING)) LIKE '%ventricular assist%' OR LOWER(CAST(pe.value AS STRING)) LIKE '%lvad%' OR LOWER(CAST(pe.value AS STRING)) LIKE '%vad%' THEN 'VAD'
      WHEN LOWER(di.label) LIKE '%assist%' OR LOWER(CAST(pe.value AS STRING)) LIKE '%assist%' OR LOWER(di.label) LIKE '%mechanical circulatory support%' THEN 'Other MCS'
      ELSE NULL
    END AS device
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  USING (itemid)
),
-- Union all device mentions and keep distinct hadm_id/device pairs
device_mentions_raw AS (
  SELECT hadm_id, subject_id, device FROM hcpcs_devices
  UNION ALL
  SELECT hadm_id, subject_id, device FROM icdproc_devices
  UNION ALL
  SELECT hadm_id, subject_id, device FROM icu_proc_devices
),
device_mentions AS (
  SELECT DISTINCT hadm_id, subject_id, device
  FROM device_mentions_raw
  WHERE device IS NOT NULL
    AND hadm_id IS NOT NULL
),
-- Count distinct device types per hadm for eligible admissions (include zeros)
devices_per_admission AS (
  SELECT
    ea.hadm_id,
    ea.subject_id,
    COALESCE(dm.device_count, 0) AS device_count
  FROM
    eligible_admissions ea
  LEFT JOIN (
    SELECT
      hadm_id,
      COUNT(DISTINCT device) AS device_count
    FROM
      device_mentions
    GROUP BY
      hadm_id
  ) dm
  ON ea.hadm_id = dm.hadm_id
)
-- Final: compute median (50th percentile) of device_count across eligible admissions
SELECT
  APPROX_QUANTILES(device_count, 2)[OFFSET(1)] AS median_distinct_mcs_devices_per_hospitalization,
  COUNT(*) AS admissions_considered
FROM
  devices_per_admission;