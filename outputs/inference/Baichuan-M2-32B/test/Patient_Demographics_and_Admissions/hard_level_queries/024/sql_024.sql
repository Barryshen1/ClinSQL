WITH index_admissions AS (
        SELECT 
          a.hadm_id,
          a.subject_id,
          a.admittime,
          a.dischtime,
          a.hospital_expire_flag,
          -- Compute age at admission: 
          EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission,
          a.insurance,
          a.admission_type,
          -- Principal diagnosis: we'll join with diagnoses_icd later
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
          ON a.subject_id = p.subject_id
        WHERE 
          p.gender = 'M'
          AND a.insurance LIKE '%Medicare%'   -- or = 'Medicare' if we know it's exact
          AND a.admission_type = 'Emergency'
          AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 76 AND 86
          AND a.hospital_expire_flag = 0   -- exclude deaths during admission
      ),
      index_with_diagnosis AS (
        SELECT 
          ia.*,
          d.icd_code,
          d.icd_version
        FROM index_admissions ia
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
          ON ia.subject_id = d.subject_id AND ia.hadm_id = d.hadm_id
        WHERE d.seq_num = 1
          AND (
            (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
            OR (d.icd_version = 9 AND d.icd_code LIKE '434%')
          )
      ),
      index_with_los AS (
        SELECT 
          *,
          DATEDIFF(dischtime, admittime) AS los
        FROM index_with_diagnosis
      ),
      -- Check for readmission within 30 days
      readmission_check AS (
        SELECT 
          i.*,
          -- Check if there is any subsequent admission within 30 days
          EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
            WHERE a2.subject_id = i.subject_id
              AND a2.hadm_id != i.hadm_id
              AND a2.admittime > i.dischtime
              AND a2.admittime <= DATE_ADD(i.dischtime, INTERVAL 30 DAY)
          ) AS readmitted
        FROM index_with_los i
      )
      -- Now aggregate by readmitted flag
      SELECT 
        readmitted,
        COUNT(*) AS num_admissions,
        COUNT(*) * 100.0 / (SELECT COUNT(*) FROM readmission_check) AS readmission_rate_percent,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) AS median_los,
        AVG(CASE WHEN los > 5 THEN 1 ELSE 0 END) * 100 AS percent_los_gt5
      FROM readmission_check
      GROUP BY readmitted
      ORDER BY readmitted;